-- End-to-end test of the intro cutscene runtime (src/IntroCutscene, docs/intro/DESIGN.md §7, §9)
-- on the Roblox mock: plays the whole cutscene with a fake clock at 60 Hz and checks that
-- everything it touched is restored afterwards.
--
--   python3 tools/bundle.py tools/tests/intro_driver.luau /tmp/intro.luau && luau /tmp/intro.luau
--
-- With the imported meshes (ReplicatedStorage.IntroAssets made like Studio's importer would,
-- from the OBJ export; see tools/tests/library_fixture.py):
--   python3 tools/tests/library_fixture.py assets/IntroAssets.obj > /tmp/f.luau
--   cat /tmp/f.luau tools/tests/intro_driver.luau > /tmp/d.luau
--   python3 tools/bundle.py /tmp/d.luau /tmp/intro.luau && luau /tmp/intro.luau
--
-- Optional globals (define them in a prepended file): LIBRARY_FIXTURE (as above),
-- INTRO_ASSETS_SCALE (import scale, default 1), INTRO_GROUND_Y (default 30),
-- INTRO_ATMOSPHERE (run the map's IslandAtmosphere LocalScript, default true),
-- INTRO_REPLAY (press F7 afterwards and check a second run, default true),
-- INTRO_DUMP_AT = { t1, t2, ... } (print the scene at those cutscene times: "DUMP t", a "CAM"
-- line with the camera CFrame components + FieldOfView, then one "P" line per visible part in
-- tools/render_driver.luau's format, for rendering what the runtime builds, DESIGN §9),
-- INTRO_FRAME_DT (default 1/60), INTRO_RIG ("R15" default, or "R6": the cutscene must skip the
-- character animation but still play and restore everything, DESIGN §4.4).
--
-- Output: "FAIL ..." lines are hard failures (the run ends with an error), "NOTE ..."
-- lines are design expectations that weren't met, "INTRO ..." lines are information.

local FRAME_DT = INTRO_FRAME_DT or 1 / 60
local MAX_SECONDS = 60
local COLOR = Color3.fromRGB(120, 200, 255)
local STAGE_SWITCH = 18.6

local fails, notes = {}, {}
local function fail(msg)
	table.insert(fails, msg)
	print("FAIL " .. msg)
end
local function note(msg)
	table.insert(notes, msg)
	print("NOTE " .. msg)
end
local function info(fmt, ...)
	print("INTRO " .. string.format(fmt, ...))
end

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

---------------------------------------------------------------- helpers
local function valueEq(a, b)
	if a == b then
		return true
	end
	if typeof(a) ~= typeof(b) then
		return false
	end
	if type(a) == "number" then
		return a ~= a and b ~= b
	end
	return false
end
local function show(v)
	if typeof(v) == "Instance" then
		return v:GetFullName()
	end
	return tostring(v)
end
local function propSnapshot(inst, only, skip)
	local t = {}
	for _, k in ipairs(only or MOCK.propertyNames(inst)) do
		if not (skip and skip[k]) then
			local ok, v = pcall(function()
				return inst[k]
			end)
			if ok then
				t[k] = { v }
			end
		end
	end
	return t
end
local function diffProps(label, inst, before, out)
	for k, box in pairs(before) do
		local ok, v = pcall(function()
			return inst[k]
		end)
		if not ok or not valueEq(v, box[1]) then
			table.insert(out, string.format("%s.%s: %s -> %s", label, k, show(box[1]), ok and show(v) or "<error>"))
		end
	end
end
local function allInstances()
	local set = {}
	for _, s in ipairs(game:GetChildren()) do
		set[s] = true
		for _, d in ipairs(s:GetDescendants()) do
			set[d] = true
		end
	end
	return set
end
local function connectionCount()
	-- every live connection on every signal of every instance in the DataModel
	local total, bySignal = 0, {}
	for inst in pairs(allInstances()) do
		local sig = rawget(inst, "__sig")
		if sig then
			for name, s in pairs(sig) do
				local n = MOCK.connectionCount(s)
				if n > 0 then
					total += n
					local key = inst.ClassName .. "." .. name
					bySignal[key] = (bySignal[key] or 0) + n
				end
			end
		end
	end
	return total, bySignal
end
local function classCountsCopy()
	return table.clone(MOCK.classCounts)
end
local function countDelta(a, b)
	local list, total = {}, 0
	for cls, n in pairs(b) do
		local d = n - (a[cls] or 0)
		if d > 0 and cls ~= "InputObject" then -- the driver's own key presses
			table.insert(list, { cls, d })
			total += d
		end
	end
	table.sort(list, function(x, y)
		return x[2] > y[2]
	end)
	local parts = {}
	for i = 1, math.min(#list, 12) do
		table.insert(parts, list[i][1] .. "=" .. list[i][2])
	end
	return total, table.concat(parts, " ")
end
local function newInstanceReport(baseline)
	-- live instances that didn't exist at the baseline, grouped by their top-most new ancestor
	local groups, total = {}, 0
	for inst in pairs(allInstances()) do
		if not baseline[inst] then
			total += 1
			local top = inst
			while top.Parent and not baseline[top.Parent] do
				top = top.Parent
			end
			local key = top:GetFullName() .. " (" .. top.ClassName .. ")"
			groups[key] = (groups[key] or 0) + 1
		end
	end
	return total, groups
end

local function shapeOf(p)
	if p:IsA("MeshPart") then
		return "M:" .. string.gsub(p.MeshId, "^fixture://", "")
	end
	if p:IsA("WedgePart") then
		return "W"
	end
	if p:FindFirstChildOfClass("SpecialMesh") then
		return "E"
	end
	local shape = p.Shape
	if shape and shape.Name == "Ball" then
		return "S"
	elseif shape and shape.Name == "Cylinder" then
		return "C"
	end
	return "B"
end
local function dumpScene(t)
	local cam = workspace.CurrentCamera
	print(string.format("DUMP %.3f", t))
	print(string.format("CAM %.4f %.4f %.4f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f", cam.CFrame:GetComponents()) .. string.format(" %.3f", cam.FieldOfView))
	for _, p in ipairs(workspace:GetDescendants()) do
		if p:IsA("BasePart") then
			local tr = 1 - (1 - p.Transparency) * (1 - p.LocalTransparencyModifier)
			if tr < 0.99 then
				local col = p.Color
				print(string.format("P %s %.2f %.2f %.2f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", shapeOf(p), p.CFrame:GetComponents())
					.. string.format(" %.2f %.2f %.2f %.3f %.3f %.3f %.2f %s", p.Size.X, p.Size.Y, p.Size.Z, col.R, col.G, col.B, tr, p.Material.Name))
			end
		end
	end
end

---------------------------------------------------------------- the world
local function buildWorld()
	MOCK.useFakeClock()
	MOCK.groundY = INTRO_GROUND_Y or 30
	local Layout = mockRequire(GENERATOR.IslandLayout)
	-- the map's lighting, sky and effects, ReplicatedStorage.IslandLayout and the IslandAtmosphere script
	mockRequire(GENERATOR.Atmosphere).Build()
	local fs = Layout.Landmarks.ForestSpawn
	local g = MOCK.groundY
	local toHub = Vector3.new(-fs.X, 0, -fs.Z).Unit
	local landing = Vector3.new(fs.X, g, fs.Z) + toHub * 14

	local island = Instance.new("Folder")
	island.Name = "Island"
	island.Parent = workspace
	local forest = Instance.new("Folder")
	forest.Name = "Forest"
	forest.Parent = island
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "IslandSpawn_Forest"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(fs.X, g + 0.5, fs.Z)
	spawn.Anchored = true
	spawn.Parent = forest
	-- real tree models from the generator, in rings around the landing point
	local Props = mockRequire(GENERATOR.Props)
	local Util = mockRequire(GENERATOR.Util)
	local templates = Props.forestTrees()
	local trees = Instance.new("Folder")
	trees.Name = "Trees"
	trees.Parent = forest
	local list = {}
	local rng = Random.new(7)
	for i, d in ipairs({ 22, 35, 50, 70, 95, 125, 160, 200, 240, 280, 315, 360, 420 }) do
		local a = i * 2.39996
		local pos = landing + Vector3.new(math.cos(a), 0, math.sin(a)) * d
		local m = Util.place(templates[(i - 1) % #templates + 1], trees, Vector3.new(pos.X, g - 1, pos.Z), rng:NextNumber(0, 6.28), 1)
		m.Name = "Tree" .. i
		table.insert(list, { model = m, d = d })
	end
	-- a tree outside the Trees folder that only has a "Trunk" piece (DESIGN §7.3: any model with a Trunk/Bark piece)
	local loose = Instance.new("Model")
	loose.Name = "LooseTree"
	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Anchored = true
	trunk.Size = Vector3.new(2, 18, 2)
	trunk.CFrame = CFrame.new(landing + Vector3.new(60, 9, -30))
	trunk.Parent = loose
	local crown = Instance.new("Part")
	crown.Name = "Crown"
	crown.Anchored = true
	crown.Shape = Enum.PartType.Ball
	crown.Size = Vector3.new(12, 12, 12)
	crown.CFrame = CFrame.new(landing + Vector3.new(60, 20, -30))
	crown.Parent = loose
	loose.WorldPivot = CFrame.new(landing + Vector3.new(60, 0, -30))
	loose.Parent = forest
	table.insert(list, { model = loose, d = (Vector3.new(60, 0, -30)).Magnitude })

	if LIBRARY_FIXTURE then
		local scale = INTRO_ASSETS_SCALE or 1
		local m = Instance.new("Model")
		m.Name = "IntroAssets"
		for _, f in ipairs(LIBRARY_FIXTURE) do
			local p = Instance.new("MeshPart")
			p.Name = f.name
			p.MeshId = "fixture://" .. f.name
			p.Size = f.size * scale
			p.CFrame = CFrame.new(f.center * scale)
			p.Anchored = true
			p.Parent = m
		end
		m.Parent = ReplicatedStorage
		info("ReplicatedStorage.IntroAssets from the fixture: %d meshes (scale %g)", #LIBRARY_FIXTURE, scale)
	else
		info("no ReplicatedStorage.IntroAssets (procedural fallback path)")
	end
	return { layout = Layout, landing = landing, toHub = toHub, spawn = spawn, trees = list }
end

---------------------------------------------------------------- state snapshot / restore checks
local function snapshot(player)
	local s = {}
	s.lighting = propSnapshot(Lighting)
	s.lightingAttrs = Lighting:GetAttributes()
	s.lightingKids = {}
	for _, d in ipairs(Lighting:GetDescendants()) do
		s.lightingKids[d] = { parent = d.Parent, props = propSnapshot(d) }
	end
	s.terrainKids = {}
	for _, d in ipairs(workspace.Terrain:GetChildren()) do
		s.terrainKids[d] = { parent = d.Parent, props = propSnapshot(d) }
	end
	s.workspace = propSnapshot(workspace, nil, { CurrentCamera = true })
	s.camera = workspace.CurrentCamera
	s.cameraProps = propSnapshot(s.camera, nil, { CFrame = true, Focus = true })
	local char = player.Character
	s.character = char
	s.charProps = {}
	for _, d in ipairs(char:GetDescendants()) do
		local only
		if d:IsA("BasePart") then
			only = { "Anchored", "CanCollide", "CanQuery", "CanTouch", "CastShadow", "Massless", "Transparency", "LocalTransparencyModifier", "Size", "Color", "Material" }
		elseif d:IsA("Motor6D") then
			only = { "Enabled", "C0", "C1", "Part0", "Part1" }
		elseif d:IsA("Humanoid") then
			only = { "HipHeight", "WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "AutoRotate", "PlatformStand", "Sit", "Health", "MaxHealth", "CameraOffset", "AutoJumpEnabled", "EvaluateStateMachine", "DisplayDistanceType", "HealthDisplayType", "RigType" }
		elseif d:IsA("BaseScript") then
			only = { "Enabled", "Disabled" }
		elseif d:IsA("Decal") then
			only = { "Transparency", "LocalTransparencyModifier" }
		end
		if only then
			s.charProps[d] = propSnapshot(d, only)
		end
	end
	s.state = char.Humanoid:GetState()
	s.coreGui = table.clone(MOCK.coreGui)
	s.core = table.clone(MOCK.core)
	s.uis = propSnapshot(UserInputService)
	s.starterGui = propSnapshot(StarterGui)
	s.instances = allInstances()
	s.connections, s.bySignal = connectionCount()
	s.bindings = table.concat(MOCK.renderBindings(), ",")
	s.actions = table.concat(MOCK.boundActions(), ",")
	s.trees = {}
	return s
end

local function checkRestored(label, s, world, player)
	local out = {}
	diffProps("Lighting", Lighting, s.lighting, out)
	local attrs = Lighting:GetAttributes()
	for k, v in pairs(attrs) do
		if not valueEq(v, s.lightingAttrs[k]) and not (k == "CutsceneActive" and v == false and s.lightingAttrs[k] == nil) then
			table.insert(out, "Lighting attribute " .. k .. ": " .. show(s.lightingAttrs[k]) .. " -> " .. show(v))
		end
	end
	for d, b in pairs(s.lightingKids) do
		if d.Parent ~= b.parent then
			table.insert(out, "Lighting child " .. d.Name .. " (" .. d.ClassName .. ") parent " .. show(b.parent) .. " -> " .. show(d.Parent))
		end
		diffProps(d:GetFullName(), d, b.props, out)
	end
	for _, d in ipairs(Lighting:GetDescendants()) do
		if not s.lightingKids[d] then
			table.insert(out, "new Lighting child " .. d:GetFullName() .. " (" .. d.ClassName .. ")")
		end
	end
	for d, b in pairs(s.terrainKids) do
		if d.Parent ~= b.parent then
			table.insert(out, "Terrain child " .. d.Name .. " parent changed")
		end
		diffProps(d:GetFullName(), d, b.props, out)
	end
	if #out == 0 then
		info("%s: Lighting, its %d effects and Terrain.Clouds restored exactly", label, (function()
			local n = 0
			for _ in pairs(s.lightingKids) do
				n += 1
			end
			return n
		end)())
	else
		for _, m in ipairs(out) do
			fail(label .. ": lighting not restored: " .. m)
		end
	end

	out = {}
	diffProps("Workspace", workspace, s.workspace, out)
	if workspace.CurrentCamera ~= s.camera then
		table.insert(out, "workspace.CurrentCamera replaced")
	end
	diffProps("Camera", workspace.CurrentCamera, s.cameraProps, out)
	for _, m in ipairs(out) do
		fail(label .. ": " .. m)
	end

	-- character
	local char = player.Character
	if char ~= s.character then
		fail(label .. ": player.Character changed (respawned?)")
		return
	end
	out = {}
	for d, props in pairs(s.charProps) do
		if d.Parent == nil then
			table.insert(out, "removed " .. d.Name)
		else
			diffProps(d:GetFullName(), d, props, out)
		end
	end
	for _, m in ipairs(out) do
		fail(label .. ": character not restored: " .. m)
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local animate = char:FindFirstChild("Animate")
	if hrp.Anchored then
		fail(label .. ": HumanoidRootPart still anchored")
	end
	if not animate or not animate.Enabled then
		fail(label .. ": Animate script not enabled")
	end
	if not MOCK.controlsEnabled then
		fail(label .. ": player controls not re-enabled")
	end
	for _, d in ipairs(char:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Decal")) and d.LocalTransparencyModifier ~= 0 then
			fail(label .. ": LocalTransparencyModifier " .. d.LocalTransparencyModifier .. " on " .. d:GetFullName())
		end
	end
	local st = char.Humanoid:GetState()
	if st == Enum.HumanoidStateType.PlatformStanding or st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Dead then
		fail(label .. ": humanoid left in state " .. st.Name)
	end
	if #char.Humanoid.Animator:GetPlayingAnimationTracks() == 0 then
		note(label .. ": no animation playing on the character afterwards (Animate restarted?)")
	end

	-- UI / input / core GUI
	for k, v in pairs(s.coreGui) do
		if MOCK.coreGui[k] ~= v then
			fail(label .. ": core GUI " .. k .. " not restored")
		end
	end
	for k, v in pairs(s.core) do
		if MOCK.core[k] ~= v then
			fail(label .. ": StarterGui:SetCore " .. k .. " not restored")
		end
	end
	out = {}
	diffProps("UserInputService", UserInputService, s.uis, out)
	diffProps("StarterGui", StarterGui, s.starterGui, out)
	for _, m in ipairs(out) do
		fail(label .. ": " .. m)
	end
	local b = table.concat(MOCK.renderBindings(), ",")
	if b ~= s.bindings then
		fail(label .. ": render step bindings left: " .. b)
	end
	local a = table.concat(MOCK.boundActions(), ",")
	if a ~= s.actions then
		fail(label .. ": ContextActionService actions left: " .. a)
	end

	-- leftover / missing instances
	local now = allInstances()
	local leftovers, allowed = {}, 0
	for inst in pairs(now) do
		if not s.instances[inst] then
			local tool = inst:IsA("Tool") and inst or inst:FindFirstAncestorOfClass("Tool")
			local grip = inst.Name == "RightGrip" and inst:IsA("JointInstance")
			if tool or grip then
				allowed += 1 -- the sword the server script gives (DESIGN §7.0)
			else
				local top = inst
				while top.Parent and not s.instances[top.Parent] do
					top = top.Parent
				end
				leftovers[top] = (leftovers[top] or 0) + 1
			end
		end
	end
	for top, n in pairs(leftovers) do
		fail(string.format("%s: leftover %s (%s, %d instances)", label, top:GetFullName(), top.ClassName, n))
	end
	for inst in pairs(s.instances) do
		if not now[inst] and inst.Name ~= "RightGrip" then
			local p = inst.Parent
			if not (p and not now[p]) then
				fail(label .. ": instance removed: " .. inst:GetFullName() .. " (" .. inst.ClassName .. ")")
			end
		end
	end

	-- connections
	local total, bySignal = connectionCount()
	if total > s.connections then
		local grew = {}
		for k, n in pairs(bySignal) do
			if n > (s.bySignal[k] or 0) then
				table.insert(grew, k .. " +" .. (n - (s.bySignal[k] or 0)))
			end
		end
		table.sort(grew)
		local toolOnly = true
		for _, gname in ipairs(grew) do
			if not string.find(gname, "^Tool%.") then
				toolOnly = false
			end
		end
		if toolOnly then
			info("%s: connections +%d, all on the given Tool", label, total - s.connections)
		else
			fail(label .. ": connections leaked: " .. table.concat(grew, ", "))
		end
	end

	-- trees back where they were
	local moved = 0
	for _, t in ipairs(world.trees) do
		local pv = t.model:GetPivot()
		if not pv:FuzzyEq(t.pivot, 1e-4) then
			moved += 1
			fail(string.format("%s: tree %s (d=%d) not restored (off by %.3f studs)", label, t.model.Name, t.d, (pv.Position - t.pivot.Position).Magnitude))
		end
	end
	if moved == 0 then
		info("%s: all %d trees back at their original pivots", label, #world.trees)
	end
end

---------------------------------------------------------------- one play-through
local function playOnce(label, Intro, world, player, starter)
	local s = snapshot(player)
	for _, t in ipairs(world.trees) do
		t.pivot = t.model:GetPivot()
		t.maxAngle = 0
	end
	local char = player.Character
	local hrp = char.HumanoidRootPart
	local motors = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") then
			table.insert(motors, d)
		end
	end
	local finishedWith, onFinishedCalled = nil, false
	local fconn = Intro.Finished:Connect(function(c)
		finishedWith = c
	end)
	local done = false
	local t0 = MOCK.clock
	local counts0 = classCountsCopy()
	local countsSwitch
	local streamBefore = #MOCK.streamRequests
	local remoteBefore = #MOCK.remoteLog
	local warnBefore = #MOCK.warnLog
	local errBefore = #MOCK.errors
	local frameTimes, slow = {}, {}
	local sampled = {}
	local animatorFrames, hiddenOk = 0, true
	local stageSamples = {}
	local camTypes = {}
	if starter then
		-- e.g. the Studio test key; the snapshot above is from before it
		starter()
		MOCK.step(FRAME_DT)
		MOCK.step(FRAME_DT)
		if not Intro.IsPlaying() then
			fconn:Disconnect()
			return false
		end
	else
		task.spawn(function()
			Intro.Play({
				color = COLOR,
				onFinished = function()
					onFinishedCalled = true
				end,
			})
			done = true
		end)
	end
	local frames = 0
	while MOCK.clock - t0 < MAX_SECONDS do
		local t = MOCK.clock - t0
		if starter and not Intro.IsPlaying() then
			done = true
		end
		if done then
			break
		end
		local ft = MOCK.step(FRAME_DT)
		frames += 1
		t = MOCK.clock - t0
		table.insert(frameTimes, ft)
		table.insert(slow, { ft, t })
		camTypes[workspace.CurrentCamera.CameraType.Name] = true
		if INTRO_DUMP_AT and not starter then
			for _, at in ipairs(INTRO_DUMP_AT) do
				if t >= at and t - FRAME_DT < at then
					dumpScene(t)
				end
			end
		end
		if not countsSwitch and t >= STAGE_SWITCH then
			countsSwitch = classCountsCopy()
		end
		-- samples during the run
		for _, at in ipairs({ 1.0, 5.0, 10.0, 16.0, 30.0, 36.0 }) do
			if not sampled[at] and t >= at then
				sampled[at] = true
				local n, groups = newInstanceReport(s.instances)
				table.insert(stageSamples, { at = at, n = n, groups = groups })
				if at == 5.0 then
					if not Intro.IsPlaying() then
						note(label .. ": IsPlaying() is false at t=5")
					end
					if Lighting:GetAttribute("CutsceneActive") ~= true then
						note(label .. ": Lighting attribute CutsceneActive not set while playing")
					end
					if MOCK.controlsEnabled then
						note(label .. ": player controls still enabled at t=5")
					end
					if workspace.CurrentCamera.CameraType ~= Enum.CameraType.Scriptable then
						note(label .. ": camera not Scriptable at t=5 (" .. workspace.CurrentCamera.CameraType.Name .. ")")
					end
					if not starter then
						-- a second Play while playing must do nothing (and return right away)
						local secondDone = false
						local before = MOCK.instanceCount
						task.spawn(function()
							Intro.Play({ color = Color3.new(1, 0, 0) })
							secondDone = true
						end)
						if not secondDone then
							fail(label .. ": a second Play() while playing yielded instead of returning")
						elseif MOCK.instanceCount - before > 2 then
							note(label .. ": a second Play() while playing created " .. (MOCK.instanceCount - before) .. " instances")
						end
					end
				end
				if at == 10.0 then
					for _, d in ipairs(char:GetDescendants()) do
						if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.LocalTransparencyModifier < 1 and d.Transparency < 1 then
							hiddenOk = false
						end
					end
					if not hiddenOk then
						note(label .. ": character not hidden during the space stage (LocalTransparencyModifier < 1 at t=10)")
					end
				end
			end
		end
		-- the Animator must not override the cutscene's pose while the character is shown
		if t > 21.0 and t < 41.0 then
			for _, m in ipairs(motors) do
				local int = rawget(m, "__int")
				if int and int.writer == "animator" and int.writeFrame == MOCK.frame then
					animatorFrames += 1
					break
				end
			end
		end
		-- tree bending
		if t > 34 and t < 42 then
			for _, tr in ipairs(world.trees) do
				local pv = tr.model:GetPivot()
				local ang = math.acos(math.clamp(pv.UpVector:Dot(tr.pivot.UpVector), -1, 1))
				if ang > tr.maxAngle then
					tr.maxAngle = ang
				end
			end
		end
	end
	local duration = MOCK.clock - t0
	if not done then
		fail(string.format("%s: Play() did not return within %d s of simulated time", label, MAX_SECONDS))
	end
	-- let deferred work, the remote and the server's sword arrive
	MOCK.run(1.0, FRAME_DT)
	fconn:Disconnect()

	info("%s: Play returned after %.2f s simulated, %d frames", label, duration, frames)
	if done and math.abs(duration - 42.5) > 1.0 then
		note(string.format("%s: duration %.2f s, the design says 42.5 s", label, duration))
	end
	if Intro.IsPlaying() then
		fail(label .. ": IsPlaying() still true after Play returned")
	end
	if not starter then
		if finishedWith ~= COLOR then
			note(label .. ": Finished did not fire with the colour (got " .. show(finishedWith) .. ")")
		end
		if not onFinishedCalled then
			note(label .. ": onFinished was not called")
		end
	end
	-- errors and warnings
	for i = errBefore + 1, #MOCK.errors do
		fail(label .. ": Lua error: " .. string.match(MOCK.errors[i], "^[^\n]*"))
	end
	local warns = {}
	for i = warnBefore + 1, #MOCK.warnLog do
		table.insert(warns, MOCK.warnLog[i])
	end
	if #warns > 0 then
		info("%s: %d warn() calls from scripts:", label, #warns)
		for i = 1, math.min(#warns, 12) do
			print("    " .. warns[i])
		end
	end
	-- frame times
	table.sort(frameTimes)
	if #frameTimes > 0 then
		local sum = 0
		for _, x in ipairs(frameTimes) do
			sum += x
		end
		table.sort(slow, function(a, b)
			return a[1] > b[1]
		end)
		local worst = {}
		for i = 1, math.min(3, #slow) do
			table.insert(worst, string.format("%.1f ms @ t=%.2f", slow[i][1] * 1000, slow[i][2]))
		end
		info("%s: frame time (mock, CPU) min %.2f ms, median %.2f ms, mean %.2f ms, max %.2f ms; slowest: %s", label,
			frameTimes[1] * 1000, frameTimes[math.ceil(#frameTimes / 2)] * 1000, sum / #frameTimes * 1000, frameTimes[#frameTimes] * 1000, table.concat(worst, ", "))
	end
	-- instances per stage
	local countsEnd = classCountsCopy()
	local n1, top1 = countDelta(counts0, countsSwitch or countsEnd)
	info("%s: instances created, space stage (t < %.1f): %d  [%s]", label, STAGE_SWITCH, n1, top1)
	if countsSwitch then
		local n2, top2 = countDelta(countsSwitch, countsEnd)
		info("%s: instances created, world stage (t >= %.1f): %d  [%s]", label, STAGE_SWITCH, n2, top2)
	else
		note(label .. ": the world stage (t >= " .. STAGE_SWITCH .. ") was never reached")
	end
	for _, smp in ipairs(stageSamples) do
		local keys = {}
		for k, n in pairs(smp.groups) do
			table.insert(keys, { k, n })
		end
		table.sort(keys, function(a, b)
			return a[2] > b[2]
		end)
		local parts = {}
		for i = 1, math.min(#keys, 6) do
			table.insert(parts, keys[i][1] .. "=" .. keys[i][2])
		end
		info("%s: t=%4.1f  %d live new instances: %s", label, smp.at, smp.n, table.concat(parts, "  "))
	end
	local camList = {}
	for k in pairs(camTypes) do
		table.insert(camList, k)
	end
	table.sort(camList)
	info("%s: camera types seen: %s", label, table.concat(camList, ", "))
	-- streaming, remote, sword
	if #MOCK.streamRequests > streamBefore then
		local r = MOCK.streamRequests[streamBefore + 1]
		info("%s: RequestStreamAroundAsync(%s) at t=%.2f (landing %s)", label, tostring(r.pos), r.t - t0, tostring(world.landing))
	else
		note(label .. ": no RequestStreamAroundAsync call (DESIGN §7.1)")
	end
	local fired = false
	for i = remoteBefore + 1, #MOCK.remoteLog do
		local r = MOCK.remoteLog[i]
		if r.remote.Name == "IntroCutscene_Finished" and r.dir == "server" then
			fired = true
			if not starter and r.args[1] ~= COLOR then
				note(label .. ": IntroCutscene_Finished fired with " .. show(r.args[1]))
			end
		end
	end
	if not fired then
		note(label .. ": IntroCutscene_Finished was not fired to the server")
	end
	local tools = {}
	for _, x in ipairs(char:GetChildren()) do
		if x:IsA("Tool") then
			table.insert(tools, x.Name .. " (in character)")
		end
	end
	for _, x in ipairs(player.Backpack:GetChildren()) do
		if x:IsA("Tool") then
			table.insert(tools, x.Name .. " (in backpack)")
		end
	end
	info("%s: tools: %s", label, #tools > 0 and table.concat(tools, ", ") or "none")
	if animatorFrames > 0 then
		fail(string.format("%s: the Animator overwrote the character's joints on %d frames while it was shown (t 21..41)", label, animatorFrames))
	end
	-- character placement
	-- R15 stands on HipHeight; R6 has HipHeight 0 and stands on its 2-stud legs
	local leg = char:FindFirstChild("Left Leg")
	local hip = char.Humanoid.RigType == Enum.HumanoidRigType.R6 and leg and leg.Size.Y or char.Humanoid.HipHeight
	local feet = hrp.Position.Y - (hip + hrp.Size.Y / 2)
	local flat = Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(world.landing.X, 0, world.landing.Z)
	info("%s: character ends %.1f studs from the landing point, feet at y=%.2f (ground %.2f), facing hub dot %.2f", label,
		flat.Magnitude, feet, MOCK.groundY, hrp.CFrame.LookVector:Dot(world.toHub))
	if math.abs(feet - MOCK.groundY) > 0.6 then
		note(string.format("%s: character's feet end %.2f studs from the ground", label, feet - MOCK.groundY))
	end
	if flat.Magnitude > 25 then
		note(string.format("%s: character ends %.1f studs away from the landing point", label, flat.Magnitude))
	end
	-- tree bending summary
	local bent, inside = 0, 0
	local radius = 320
	for _, tr in ipairs(world.trees) do
		if tr.d <= radius then
			inside += 1
			if tr.maxAngle > 0.01 then
				bent += 1
			end
		elseif tr.maxAngle > 1e-4 then
			note(string.format("%s: tree %s at %d studs (outside WIND_RADIUS) moved", label, tr.model.Name, tr.d))
		end
	end
	local angles = {}
	for _, tr in ipairs(world.trees) do
		table.insert(angles, string.format("%d:%.2f", tr.d, tr.maxAngle))
	end
	info("%s: trees bent %d of %d inside the wind radius (max angle by distance: %s)", label, bent, inside, table.concat(angles, " "))
	if bent == 0 then
		note(label .. ": no tree bent by the shockwave wind")
	end
	checkRestored(label, s, world, player)
	return true
end

---------------------------------------------------------------- main
local function main()
	print("INTRO DRIVER: mock run of src/IntroCutscene")
	if not INTRO then
		print("INTRO SKIP: src/IntroCutscene was not found, nothing to test (the runtime isn't written yet)")
		return
	end
	if not INTRO:IsA("ModuleScript") then
		fail("src/IntroCutscene has no init.luau (ReplicatedStorage.IntroCutscene is a " .. INTRO.ClassName .. ")")
		return
	end
	local world = buildWorld()
	local player = MOCK.setupClient({
		rig = INTRO_RIG or "R15",
		spawn = CFrame.lookAt(world.spawn.Position + Vector3.new(0, 3.5, 0), world.spawn.Position + Vector3.new(0, 3.5, 0) + world.toHub),
	})
	info("landing point %s, ground y=%g, %d trees", tostring(world.landing), MOCK.groundY, #world.trees)
	-- the map's own client script, like in a real game
	if INTRO_ATMOSPHERE ~= false then
		local atm = player.PlayerScripts:FindFirstChild("IslandAtmosphere")
		if atm then
			runScript(atm)
			info("running the map's IslandAtmosphere LocalScript")
		end
	end
	-- the cutscene's server script (creates the RemoteEvent, gives the sword)
	local server = INTRO:FindFirstChild("Server")
	if server and server:IsA("Script") then
		if not runScript(server) then
			fail("Server script would not run (RunContext must be Server)")
		end
	else
		note("no Server script in IntroCutscene (DESIGN §7.0)")
	end
	MOCK.run(6.0, FRAME_DT) -- settle: banner tweens, weather, the server's RemoteEvent
	local n0 = MOCK.instanceCount
	local ok, Intro = xpcall(function()
		return mockRequire(INTRO)
	end, debug.traceback)
	if not ok then
		fail("require(IntroCutscene) errored:\n" .. tostring(Intro))
		return
	end
	info("require(IntroCutscene) ok, %d instances created at load", MOCK.instanceCount - n0)
	if type(Intro) ~= "table" or type(Intro.Play) ~= "function" or type(Intro.IsPlaying) ~= "function" then
		fail("IntroCutscene must return a table with Play and IsPlaying functions (DESIGN §7.0)")
		return
	end
	if typeof(Intro.Finished) ~= "RBXScriptSignal" then
		note("Intro.Finished is not an RBXScriptSignal (DESIGN §7.0)")
		Intro.Finished = MOCK.newSignal("dummy")
	end
	if not ReplicatedStorage:FindFirstChild("IntroCutscene_Finished") then
		note("ReplicatedStorage.IntroCutscene_Finished RemoteEvent missing before Play")
	end
	if Intro.IsPlaying() then
		fail("IsPlaying() is true before Play")
	end
	MOCK.run(0.5, FRAME_DT)

	playOnce("PLAY", Intro, world, player)

	if INTRO_REPLAY ~= false and MOCK.studio then
		-- Studio test key (DESIGN §7.0); a second full run also catches state that leaks between runs
		local replayed = playOnce("REPLAY", Intro, world, player, function()
			MOCK.tapKey(Enum.KeyCode.F7)
		end)
		if replayed then
			info("F7 replayed the intro (Studio test key)")
		else
			note("pressing F7 in Studio did not replay the intro")
		end
	end

	for msg, n in pairs(MOCK.warnings) do
		fail(string.format("MOCKWARN x%d %s", n, msg))
	end
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
	fail("driver error: " .. tostring(err))
end
print(string.format("INTRO SUMMARY: %d failures, %d notes", #fails, #notes))
if #fails > 0 then
	print("INTRO FAILED")
	error("intro driver: " .. #fails .. " failures", 0)
end
if INTRO then
	print("INTRO OK")
end
