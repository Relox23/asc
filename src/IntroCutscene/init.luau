--[[
	IntroCutscene  ("Awaken", docs/intro/DESIGN.md)
	ModuleScript for ReplicatedStorage. Plays back the Blender-authored intro
	(IntroData + IntroAssets) with the player's real avatar.

	    local Intro = require(game.ReplicatedStorage:WaitForChild("IntroCutscene"))
	    Intro.Play({
	        color = Color3.fromRGB(120, 200, 255), -- soul core colour (required)
	        onFinished = function(color) end,      -- optional
	    })                                          -- yields until the cutscene ends
	    Intro.IsPlaying() -> boolean
	    Intro.Finished    -- RBXScriptSignal (BindableEvent.Event), fires with the colour

	Play must be called from a LocalScript; while playing, further calls do
	nothing. In Studio, pressing Config.TEST_IN_STUDIO_KEY (F7) during a play test
	plays it with Config.TEST_COLOR. When it ends (normally, skipped, aborted or
	after an error) everything is restored, the RemoteEvent
	ReplicatedStorage.IntroCutscene_Finished is fired with the colour (the server
	script gives the sword), Finished fires and onFinished is called.

	Frame loop
	  * RunService:BindToRenderStep("IntroCutscene", Camera + 1): the clock advances
	    (by real frame time, at most Config.MAX_FRAME_DT per frame), every marker
	    with time <= t fires once, in order (even when a frame jumps over several),
	    then Update(t) sets everything for time t: camera, character, the active
	    stage, the screen. Every frame runs inside xpcall: an error is logged
	    and the cutscene stops cleanly.
	  * RunService.PreSimulation (after the Animator): CharacterRig:ApplyJoints()
	    re-applies this frame's Motor6D Transforms so nothing overwrites them.
	  * Character death / removal / respawn or the player leaving aborts the
	    cutscene (everything restored, Finished still fires).

	Markers handled here: bars, fade, flash, shake, impact, speedlines (Screen),
	stage:world (stage switch), sound:<name>, end. Every marker is also passed to
	both stages' OnMarker (cut, wind, shockwave, resonate, morph, ...).

	Stage interface (SpaceStage.luau, WorldStage.luau)
	    Stage.new(ctx) -> stage       build everything (parent it under ctx.root); called at start
	    stage:SetActive(active)       space is active for t < stageSwitch, world after
	    stage:Update(t, dt)           only called while active; the camera (ctx.cameraCF) and the
	                                  character (ctx.character) are already set for t
	    stage:OnMarker(kind, args, t) every marker, active or not (t = the marker's own time)
	    stage:Destroy()               remove everything it made (called once at the end)

	ctx (shared by the stages)
	    color        Color3     soul core colour
	    data         table      IntroData
	    timeline     Timeline   (Timeline.luau)
	    assets       Assets     module (Assets.luau)
	    screen       Screen     (AddSilhouette for impact frames, Flash, Shake, ...)
	    lighting     LightingFX (Set / Effect for extra tweaks, restored automatically)
	    character    CharacterRig (GripCF, PartCFrame, root, character, ...)
	    origins      { space = CFrame, world = CFrame }  stage origins (§2). origins.world may
	                 be refined right before the world stage starts (landing found only after
	                 streaming), so read it in SetActive(true)/Update, don't cache it in new()
	    origin(stage, t) -> CFrame  origin for a track's `stage` field ("camera" = by time)
	    landing      Vector3    landing point on the ground (also refined like origins.world)
	    camera       Camera     workspace.CurrentCamera (Scriptable while playing)
	    cameraCF     CFrame     this frame's camera CFrame (incl. shake)
	    root         Folder     workspace.IntroCutscene, holds everything created
	    config       Config
	    player       Player
	    t            number     current cutscene time
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(script.Config)
local Convert = require(script.Convert)
local Timeline = require(script.Timeline)
local Assets = require(script.Assets)
local Screen = require(script.Screen)
local LightingFX = require(script.LightingFX)
local CharacterRig = require(script.CharacterRig)
local SpaceStage = require(script.SpaceStage)
local WorldStage = require(script.WorldStage)

local Intro = {}

local RENDER_STEP = "IntroCutscene"
local REMOTE_NAME = "IntroCutscene_Finished"
local SKIP_FADE = 0.35
local WHITE = Color3.new(1, 1, 1)

local finishedEvent = Instance.new("BindableEvent")
finishedEvent.Name = "IntroCutsceneFinished"
Intro.Finished = finishedEvent.Event

local current = nil -- the running session

local function log(...)
	print("[IntroCutscene]", ...)
end

local function warnf(...)
	warn("[IntroCutscene]", ...)
end

local function try(what, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnf("cleanup step '" .. what .. "' failed: " .. tostring(err))
	end
	return ok
end

local function notifyServer(color)
	task.spawn(function()
		local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME) or ReplicatedStorage:WaitForChild(REMOTE_NAME, 5)
		if remote and remote:IsA("RemoteEvent") then
			remote:FireServer(color)
		end
	end)
end

-- Landing point (DESIGN §7.1) ----------------------------------------------------------------------------
local function groundAt(x, z, exclude)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	params.RespectCanCollide = true -- leaves, clouds and effects are not the ground
	local hit = workspace:Raycast(Vector3.new(x, 5000, z), Vector3.new(0, -10000, 0), params)
	return hit and hit.Position.Y or nil
end

local function exclusions(extra)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, inst in ipairs(extra) do
		table.insert(list, inst)
	end
	return list
end

local HUB = Vector3.zero

-- -> ground point (Vector3), direction toward the hub (Vector3), provisional (ground not found yet)
local function findLanding(character, root)
	local spec = Config.LANDING
	local specType = typeof(spec)
	if specType == "Vector3" then
		return spec, HUB - spec, false
	end
	local exclude = exclusions({ root })
	local xz
	local layoutModule = ReplicatedStorage:FindFirstChild("IslandLayout")
	if layoutModule and layoutModule:IsA("ModuleScript") then
		local ok, layout = pcall(require, layoutModule)
		local spawnXZ = ok and type(layout) == "table" and layout.Landmarks and layout.Landmarks.ForestSpawn
		local spawnType = typeof(spawnXZ)
		if spawnType == "Vector3" then
			xz = Vector3.new(spawnXZ.X, 0, spawnXZ.Z)
		end
	end
	local spawn = workspace:FindFirstChild("IslandSpawn_Forest", true)
	if not (spawn and spawn:IsA("BasePart")) then
		spawn = nil
	end
	if not xz and spawn then
		xz = Vector3.new(spawn.Position.X, 0, spawn.Position.Z)
	end
	if xz then
		local toHub = HUB - xz
		if toHub.Magnitude > 1e-3 then
			xz += toHub.Unit * math.min(Config.LANDING_OFFSET_TO_HUB or 14, toHub.Magnitude)
		end
		local y = groundAt(xz.X, xz.Z, exclude)
		if y then
			return Vector3.new(xz.X, y, xz.Z), HUB - xz, false
		end
		if spawn then
			return Vector3.new(xz.X, spawn.Position.Y - 1.6, xz.Z), HUB - xz, true
		end
	end
	-- no island: land where the character is
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChildOfClass("Humanoid")
	local pos = hrp and hrp.Position or Vector3.zero
	local p = xz or Vector3.new(pos.X, 0, pos.Z)
	local y = groundAt(p.X, p.Z, exclude)
	if y then
		return Vector3.new(p.X, y, p.Z), xz and (HUB - xz) or (hrp and hrp.CFrame.LookVector or Vector3.zAxis), false
	end
	local feet = pos.Y - ((hum and hum.HipHeight or 2) + (hrp and hrp.Size.Y / 2 or 1))
	return Vector3.new(p.X, feet, p.Z), xz and (HUB - xz) or (hrp and hrp.CFrame.LookVector or Vector3.zAxis), true
end

-- Session ---------------------------------------------------------------------------------------------------
local Session = {}
Session.__index = Session

function Session.new(color, onFinished)
	local self = setmetatable({}, Session)
	self.color = color
	self.onFinished = onFinished
	self.player = Players.LocalPlayer
	self.camera = workspace.CurrentCamera
	self.t = 0
	self.done = false
	self.connections = {}
	self.doneEvent = Instance.new("BindableEvent")
	return self
end

function Session:_connect(signal, fn)
	table.insert(self.connections, signal:Connect(fn))
end

function Session:_waitCharacter()
	local player = self.player
	local deadline = os.clock() + 15
	while os.clock() < deadline do
		local c = player.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if c and hum and hum.Health > 0 and c:FindFirstChild("HumanoidRootPart") and c:IsDescendantOf(workspace) then
			return c
		end
		task.wait(0.1)
	end
	return nil
end

function Session:_setWorldOrigin()
	local height = (self.data.world and self.data.world.landingHeight) or 0
	local origin = Convert.stageOrigin(self.landing - Vector3.new(0, height, 0), self.toHub)
	self.origins.world = origin
	if self.ctx then
		self.ctx.landing = self.landing
	end
end

function Session:_refineLanding()
	self.landingProvisional = false
	local y = groundAt(self.landing.X, self.landing.Z, exclusions({ self.root }))
	if y then
		self.landing = Vector3.new(self.landing.X, y, self.landing.Z)
		self:_setWorldOrigin()
	end
end

function Session:start()
	local player = self.player
	assert(player, "IntroCutscene.Play must be called from a LocalScript")
	local character = self:_waitCharacter()
	assert(character, "no living character to play the intro with")

	self.data = require(script.IntroData)
	local tl = Timeline.new(self.data)
	self.timeline = tl
	self.cameraTrack = tl:track("Camera")

	local old = workspace:FindFirstChild("IntroCutscene")
	if old and old:IsA("Folder") then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "IntroCutscene"
	root.Parent = workspace
	self.root = root

	self.landing, self.toHub, self.landingProvisional = findLanding(character, root)
	self.origins = { space = Config.SPACE_ORIGIN }
	self:_setWorldOrigin()
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(self.landing)
		end)
	end)
	task.spawn(Assets.preload)

	local cam = self.camera
	self.savedCamera = { CameraType = cam.CameraType, CameraSubject = cam.CameraSubject, FieldOfView = cam.FieldOfView, Focus = cam.Focus }
	cam.CameraType = Enum.CameraType.Scriptable

	self.lighting = LightingFX.new(cam)
	self.lighting:Begin()
	self.screen = Screen.new(player, cam, Config)
	local rig = CharacterRig.new(player, character, root)
	self.rig = rig
	rig:SetColor(self.color)
	rig:Takeover()

	local ctx = {
		color = self.color,
		data = self.data,
		timeline = tl,
		assets = Assets,
		screen = self.screen,
		lighting = self.lighting,
		character = rig,
		origins = self.origins,
		landing = self.landing,
		camera = cam,
		cameraCF = cam.CFrame,
		root = root,
		config = Config,
		player = player,
		t = 0,
	}
	function ctx.origin(stage, t)
		if stage == "space" then
			return ctx.origins.space
		elseif stage == "world" then
			return ctx.origins.world
		end
		return tl:stageAt(t) == "world" and ctx.origins.world or ctx.origins.space
	end
	self.ctx = ctx

	self.space = SpaceStage.new(ctx)
	self.world = WorldStage.new(ctx)
	self.stages = { self.space, self.world }
	self.screen:AddSilhouette("character", character, function(part)
		return rig:PartCFrame(part)
	end)
	self.stage = "space"
	self.lighting:Space()
	self.world:SetActive(false)
	self.space:SetActive(true)

	self.cursor = tl:cursor()
	self.onMarker = function(m)
		self:_marker(m)
	end

	local hum = rig.humanoid
	self:_connect(hum.Died, function()
		self:abort("the character died")
	end)
	self:_connect(player.CharacterRemoving, function()
		self:abort("the character was removed")
	end)
	self:_connect(player.CharacterAdded, function()
		self:abort("the character respawned")
	end)
	self:_connect(character.AncestryChanged, function()
		if not character:IsDescendantOf(workspace) then
			self:abort("the character left the workspace")
		end
	end)
	self:_connect(Players.PlayerRemoving, function(p)
		if p == player then
			self:abort("the player left")
		end
	end)
	if Config.ALLOW_SKIP then
		self.screen:SetSkipHint(true)
		self:_connect(UserInputService.InputBegan, function(input, processed)
			if processed then
				return
			end
			local k = input.KeyCode
			if k == Enum.KeyCode.Space or k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonA or input.UserInputType == Enum.UserInputType.Touch then
				self:skip()
			end
		end)
	end

	-- first frame now, so nothing of the world shows before the cutscene does
	self:_frame(0)
	if self.done then
		return
	end
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_STEP)
	end)
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:_step(dt)
	end)
	self:_connect(RunService.PreSimulation, function()
		if not self.done then
			local ok, err = pcall(rig.ApplyJoints, rig)
			if not ok then
				warnf("joints: " .. tostring(err))
			end
		end
	end)
end

-- Markers ----------------------------------------------------------------------------------------------------
function Session:_sound(name)
	local id = Config.SOUNDS and Config.SOUNDS[name]
	if type(id) == "number" then
		id = "rbxassetid://" .. tostring(id)
	end
	if type(id) ~= "string" or id == "" then
		return
	end
	if string.match(id, "^%d+$") then
		id = "rbxassetid://" .. id
	end
	local s = Instance.new("Sound")
	s.Name = "IntroSound_" .. tostring(name)
	s.SoundId = id
	s.Volume = 0.8
	s.Parent = self.root
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

function Session:_switchStage(name)
	if name ~= "world" or self.stage == "world" then
		return
	end
	self.stage = "world"
	if self.landingProvisional then
		self:_refineLanding()
	end
	self.space:SetActive(false)
	self.lighting:World()
	self.world:SetActive(true)
end

function Session:_marker(m)
	local kind, args, mt = m.kind, m.args, m.t
	if Config.DEBUG then
		log(string.format("%.3f  %s", mt, m.name))
	end
	local screen = self.screen
	if kind == "bars" then
		screen:Bars(args[1] == "in", tonumber(args[2]) or 1, mt)
	elseif kind == "fade" then
		screen:Fade(args[1] == "to_black", tonumber(args[2]) or 1, mt)
	elseif kind == "flash" then
		screen:Flash(args[1] == "core" and self.color or WHITE, tonumber(args[2]) or 0.3, mt)
	elseif kind == "shake" then
		screen:Shake(tonumber(args[1]) or 0.5, tonumber(args[2]) or 0.5, mt)
	elseif kind == "impact" then
		screen:Impact(args[1], mt)
	elseif kind == "speedlines" then
		screen:SpeedLines(args[1] == "on", mt)
	elseif kind == "stage" then
		self:_switchStage(args[1])
	elseif kind == "sound" then
		self:_sound(args[1])
	elseif kind == "end" then
		self.endRequested = true
	end
	for _, stage in ipairs(self.stages) do
		stage:OnMarker(kind, args, mt)
	end
end

-- Frames -----------------------------------------------------------------------------------------------------
-- Everything for time t (markers up to t have fired).
function Session:Update(t, dt)
	local tl = self.timeline
	if self.stage ~= "world" and tl:stageAt(t) == "world" then
		self:_switchStage("world") -- in case the data has no stage:world marker
	end
	local ctx = self.ctx
	ctx.t = t
	local cam = self.camera
	local track = self.cameraTrack
	if track then
		local s = track:sample(t)
		local cf = Convert.cameraCF(ctx.origin(track.stage, t), s.pos, s.rot) * self.screen:ShakeOffset(t)
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		cam.CFrame = cf
		cam.Focus = cf * CFrame.new(0, 0, -12)
		local fov = s.channels.fov
		if fov then
			cam.FieldOfView = math.clamp(fov, 1, 120)
		end
		ctx.cameraCF = cf
	else
		ctx.cameraCF = cam.CFrame
	end
	-- the character before the stage, so the stage sees this frame's hand (sword grip)
	local cs = tl:character(t)
	if cs then
		self.rig:Update(t, cs, self.origins.world)
	end
	local stage = self.stage == "world" and self.world or self.space
	stage:Update(t, dt)
	self.screen:Update(t, dt)
end

function Session:_frame(dt)
	local tl = self.timeline
	local t = math.min(self.t + dt, tl.duration)
	self.t = t
	self.cursor:advance(t, self.onMarker)
	if self.done then
		return
	end
	self:Update(t, dt)
	if self.done then
		return
	end
	if self.skipT and t >= self.skipT + SKIP_FADE + 0.05 then
		self:finish("skipped")
	elseif self.endRequested or t >= tl.duration then
		self:finish("done")
	end
end

function Session:_step(dt)
	if self.done then
		return
	end
	local ok, err = xpcall(self._frame, debug.traceback, self, math.min(dt, Config.MAX_FRAME_DT or 0.25))
	if not ok then
		warnf("error, stopping the cutscene: " .. tostring(err))
		self:finish("error")
	end
end

function Session:skip()
	if self.done or self.skipT then
		return
	end
	self.skipT = self.t
	self.screen:SetSkipHint(false)
	self.screen:Fade(true, SKIP_FADE, self.t)
end

function Session:abort(reason)
	if self.done then
		return
	end
	warnf("stopped: " .. reason)
	self:finish("aborted")
end

-- Ending -----------------------------------------------------------------------------------------------------
function Session:_cleanup(finalCF)
	try("render step", function()
		RunService:UnbindFromRenderStep(RENDER_STEP)
	end)
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	table.clear(self.connections)
	for _, stage in ipairs(self.stages or {}) do
		try("stage", stage.Destroy, stage)
	end
	if self.screen then
		try("screen", self.screen.Destroy, self.screen)
	end
	if self.rig then
		try("character", self.rig.Restore, self.rig, finalCF)
	end
	if self.lighting then
		try("lighting", self.lighting.Restore, self.lighting)
	end
	local saved = self.savedCamera
	if saved then
		try("camera", function()
			local cam = self.camera
			cam.CameraType = saved.CameraType
			local subject = saved.CameraSubject
			if not (subject and subject.Parent) then
				local c = self.player.Character
				subject = c and c:FindFirstChildOfClass("Humanoid")
			end
			if subject then
				cam.CameraSubject = subject
			end
			cam.FieldOfView = saved.FieldOfView
			cam.Focus = saved.Focus
		end)
	end
	if self.root then
		try("folder", self.root.Destroy, self.root)
	end
end

function Session:finish(reason)
	if self.done then
		return
	end
	self.done = true
	self.reason = reason
	local finalCF
	if reason ~= "aborted" then
		pcall(function()
			local tl = self.timeline
			local cs = tl and tl:character(tl.duration)
			if cs and self.rig and self.origins then
				finalCF = self.rig:RootCF(cs, self.origins.world)
			end
		end)
	end
	self:_cleanup(finalCF)
	if current == self then
		current = nil
	end
	local color = self.color
	notifyServer(color)
	finishedEvent:Fire(color)
	if self.onFinished then
		task.spawn(function()
			local ok, err = pcall(self.onFinished, color)
			if not ok then
				warnf("onFinished: " .. tostring(err))
			end
		end)
	end
	self.doneEvent:Fire(reason)
end

-- Public API -------------------------------------------------------------------------------------------------
function Intro.IsPlaying()
	return current ~= nil
end

function Intro.Play(options)
	if current then
		return
	end
	if not RunService:IsClient() or not Players.LocalPlayer then
		warnf("Play must be called from a LocalScript")
		return
	end
	options = options or {}
	local color = options.color
	local colorType = typeof(color)
	if colorType ~= "Color3" then
		warnf("Play needs options.color (a Color3); using Config.TEST_COLOR")
		color = Config.TEST_COLOR
	end
	local session = Session.new(color, options.onFinished)
	current = session
	local ok, err = xpcall(session.start, debug.traceback, session)
	if not ok then
		warnf("could not play the intro: " .. tostring(err))
		session:finish("error")
	end
	if not session.done then
		session.doneEvent.Event:Wait()
	end
	session.doneEvent:Destroy()
end

-- Studio play tests: replay with the test colour
if RunService:IsStudio() and RunService:IsClient() then
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Config.TEST_IN_STUDIO_KEY and not current then
			task.spawn(Intro.Play, { color = Config.TEST_COLOR })
		end
	end)
end

return Intro
