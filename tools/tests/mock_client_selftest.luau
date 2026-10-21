-- Self-test of the client-side simulation in tools/mock/roblox_mock.luau (strictness,
-- value types, scheduler, frame order, tweens, joint solving, Animator, camera, input...).
--   python3 tools/bundle.py tools/tests/mock_client_selftest.luau /tmp/st.luau && luau /tmp/st.luau
local checks, failures = 0, 0
local function check(name, cond, detail)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
	end
end
local function near(a, b, tol)
	tol = tol or 1e-6
	if type(a) == "number" then
		return math.abs(a - b) <= tol
	elseif typeof(a) == "Vector3" then
		return (a - b).Magnitude <= tol
	elseif typeof(a) == "CFrame" then
		return a:FuzzyEq(b, tol)
	elseif typeof(a) == "Color3" then
		return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) <= tol
	end
	return a == b
end
local function errors(fn, pattern)
	local ok, err = pcall(fn)
	if ok then
		return false, "no error"
	end
	if pattern and not string.find(tostring(err), pattern, 1, true) then
		return false, err
	end
	return true, err
end
local function clearWarnings()
	for k in pairs(MOCK.warnings) do
		MOCK.warnings[k] = nil
	end
end

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

---------------------------------------------------------------- value types
do
	check("typeof Vector3", typeof(Vector3.new()) == "Vector3")
	check("typeof CFrame", typeof(CFrame.new()) == "CFrame")
	check("typeof Color3", typeof(Color3.new()) == "Color3")
	check("typeof UDim2", typeof(UDim2.new()) == "UDim2")
	check("typeof Instance", typeof(Instance.new("Part")) == "Instance")
	check("typeof EnumItem", typeof(Enum.KeyCode.F7) == "EnumItem")
	check("typeof signal", typeof(RunService.Heartbeat) == "RBXScriptSignal")
	check("enum values", Enum.RenderPriority.Camera.Value == 200 and Enum.RenderPriority.Character.Value == 300 and Enum.RenderPriority.Last.Value == 2000 and Enum.KeyCode.F7.Value == 288)
	check("enum type", Enum.KeyCode.F7.EnumType == Enum.KeyCode and Enum.KeyCode.F7:IsA("KeyCode"))
	check("unknown enum item errors", (errors(function()
		return Enum.KeyCode.Nope
	end)))
	check("unknown enum type errors", (errors(function()
		return Enum.DepthMode
	end)))
	-- quaternion constructor: 90 degrees about Y
	local s = math.sqrt(0.5)
	local q = CFrame.new(1, 2, 3, 0, s, 0, s)
	check("CFrame quaternion", near(q, CFrame.new(1, 2, 3) * CFrame.Angles(0, math.pi / 2, 0), 1e-9))
	local a = CFrame.Angles(0.3, -1.1, 0.7)
	local rx, ry, rz = a:ToEulerAnglesXYZ()
	check("ToEulerAnglesXYZ roundtrip", near(CFrame.Angles(rx, ry, rz), a, 1e-9))
	local ox, oy, oz = a:ToOrientation()
	check("ToOrientation roundtrip", near(CFrame.fromOrientation(ox, oy, oz), a, 1e-9))
	local l = CFrame.new():Lerp(CFrame.new(10, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), 0.5)
	check("CFrame:Lerp slerps", near(l, CFrame.new(5, 0, 0) * CFrame.Angles(0, math.pi / 4, 0), 1e-9))
	check("Color3 ==", Color3.fromRGB(10, 20, 30) == Color3.fromRGB(10, 20, 30))
	check("UDim2 math", UDim2.new(0.5, 10, 1, -5) + UDim2.fromOffset(5, 5) == UDim2.new(0.5, 15, 1, 0))
	check("NumberRange min>max errors", (errors(function()
		return NumberRange.new(2, 1)
	end)))
	check("NumberSequence order errors", (errors(function()
		return NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	end)))
	check("Vector3 lowercase errors", (errors(function()
		return Vector3.new().x
	end)))
	check("CFrame immutable", (errors(function()
		local c = CFrame.new()
		c.X = 1
	end)))
	local h, sat, v = Color3.fromHSV(0.6, 0.5, 0.8):ToHSV()
	check("HSV roundtrip", near(h, 0.6, 1e-9) and near(sat, 0.5, 1e-9) and near(v, 0.8, 1e-9))
end

---------------------------------------------------------------- strict instances
do
	local f = Instance.new("Frame")
	check("unknown property write errors", (errors(function()
		f.Sizee = UDim2.new()
	end, "no property")))
	check("wrong type errors", (errors(function()
		f.Size = Vector2.new(1, 1)
	end, "UDim2 expected")))
	check("unknown member read errors", (errors(function()
		return f.Nope
	end, "not a valid member")))
	check("abstract class not creatable", (errors(function()
		Instance.new("BasePart")
	end)))
	check("read-only errors", (errors(function()
		workspace.CurrentCamera.ViewportSize = Vector2.new(1, 1)
	end, "read only")))
	check("bad property signal errors", (errors(function()
		f:GetPropertyChangedSignal("Nope")
	end, "not a valid property")))
	check("properties have defaults", f.BackgroundTransparency == 0 and f.Visible == true and f.Size == UDim2.new(0, 100, 0, 100))
	local cam = Instance.new("Camera")
	cam.CameraType = "Scriptable"
	check("enum string coercion", cam.CameraType == Enum.CameraType.Scriptable)
	check("wrong enum type errors", (errors(function()
		cam.CameraType = Enum.KeyCode.A
	end)))
	cam.FieldOfView = 150
	check("FieldOfView clamped + warned", cam.FieldOfView == 120 and next(MOCK.warnings) ~= nil)
	clearWarnings()
	local p = Instance.new("Part")
	p:Destroy()
	check("Parent locked after Destroy", (errors(function()
		p.Parent = workspace
	end, "locked")))
	local a, b = Instance.new("Folder"), Instance.new("Folder")
	b.Parent = a
	check("circular parent errors", (errors(function()
		a.Parent = b
	end, "circular")))
	check("attribute types", (errors(function()
		a:SetAttribute("x", {})
	end)))
	a:SetAttribute("x", Vector3.one)
	check("attribute roundtrip", a:GetAttribute("x") == Vector3.one and a:GetAttributes().x == Vector3.one)
	check("services strict", (errors(function()
		game:GetService("Lighting").Brightnes = 2
	end)))
	check("GetFullName", b:GetFullName() == "Folder.Folder")
	check("Roblox class tree", Instance.new("SpecialMesh"):IsA("DataModelMesh") and Instance.new("Part"):IsA("FormFactorPart") and Instance.new("MeshPart"):IsA("TriangleMeshPart") and workspace:IsA("WorldRoot") and Instance.new("LocalScript"):IsA("Script"))
	local bp1, bp2 = Instance.new("Part"), Instance.new("Part")
	local cfSeen = 0
	bp1:GetPropertyChangedSignal("CFrame"):Connect(function()
		cfSeen += 1
	end)
	workspace:BulkMoveTo({ bp1, bp2 }, { CFrame.new(1, 2, 3), CFrame.new(4, 5, 6) }, Enum.BulkMoveMode.FireCFrameChanged)
	check("BulkMoveTo", bp1.Position == Vector3.new(1, 2, 3) and bp2.CFrame == CFrame.new(4, 5, 6) and cfSeen == 1)
	check("BulkMoveTo validates", (errors(function()
		workspace:BulkMoveTo({ bp1 }, {})
	end)))
	a.Parent = workspace
	check("IsDescendantOf", b:IsDescendantOf(workspace) and b:FindFirstAncestorOfClass("Workspace") == workspace)
	a:Destroy()
end

---------------------------------------------------------------- signals
do
	local part = Instance.new("Part")
	local changedProps = {}
	part.Changed:Connect(function(k)
		table.insert(changedProps, k)
	end)
	local sizeFired = 0
	local conn = part:GetPropertyChangedSignal("Size"):Connect(function()
		sizeFired += 1
	end)
	part.Size = Vector3.new(1, 2, 3)
	part.Size = Vector3.new(1, 2, 3) -- unchanged: no event
	part.Transparency = 0.5
	check("Changed fires with names", changedProps[1] == "Size" and changedProps[2] == "Transparency" and #changedProps == 2, table.concat(changedProps, ","))
	check("property signal", sizeFired == 1)
	conn:Disconnect()
	check("Disconnect", not conn.Connected)
	part.Size = Vector3.new(2, 2, 2)
	check("disconnected handler not called", sizeFired == 1)
	local be = Instance.new("BindableEvent")
	local onceN = 0
	be.Event:Once(function()
		onceN += 1
	end)
	be:Fire()
	be:Fire()
	check("Once", onceN == 1)
	local got
	task.spawn(function()
		got = { be.Event:Wait() }
	end)
	be:Fire("a", 2)
	check("Wait in a thread", got and got[1] == "a" and got[2] == 2)
	check("Wait on main thread errors", (errors(function()
		be.Event:Wait()
	end)))
	local folder = Instance.new("Folder")
	local added, destroying, ancestry = nil, false, nil
	folder.ChildAdded:Connect(function(c)
		added = c
	end)
	local child = Instance.new("Part")
	child.Destroying:Connect(function()
		destroying = true
	end)
	child.AncestryChanged:Connect(function(_, parent)
		ancestry = parent
	end)
	child.Parent = folder
	check("ChildAdded", added == child)
	check("AncestryChanged", ancestry == folder)
	folder:Destroy()
	check("Destroying", destroying)
	-- errors inside handlers are reported, not thrown
	print("(the next MOCKERROR \"boom\" is expected)")
	local be2 = Instance.new("BindableEvent")
	be2.Event:Connect(function()
		error("boom")
	end)
	be2:Fire()
	check("handler errors are captured", #MOCK.errors == 1)
	table.clear(MOCK.errors)
end

---------------------------------------------------------------- scheduler
do
	check("task.wait on main thread does not block", task.wait(1) == 1)
	local t0 = MOCK.clock
	local resumedAt, elapsed
	task.spawn(function()
		elapsed = task.wait(0.5)
		resumedAt = MOCK.clock
	end)
	local order = {}
	task.defer(function()
		table.insert(order, "defer")
	end)
	task.spawn(function()
		table.insert(order, "spawn")
	end)
	local delayed
	task.delay(0.25, function(x)
		delayed = x
	end, "arg")
	local cancelled = false
	local th = task.delay(0.1, function()
		cancelled = true
	end)
	task.cancel(th)
	check("spawn runs now, defer later", order[1] == "spawn" and #order == 1)
	MOCK.step(1 / 60)
	check("defer ran in the next step", order[2] == "defer")
	for _ = 1, 29 do
		MOCK.step(1 / 60)
		if resumedAt then
			break
		end
	end
	check("task.wait resumes once the clock passed", resumedAt ~= nil and resumedAt - t0 >= 0.5 - 1e-9 and resumedAt - t0 < 0.5 + 1 / 60, resumedAt and resumedAt - t0)
	check("task.wait returns elapsed time", elapsed and near(elapsed, resumedAt - t0, 1e-9))
	check("task.delay with args", delayed == "arg")
	check("task.cancel", not cancelled)
	-- frame order
	local seq = {}
	local function rec(name)
		return function()
			table.insert(seq, name)
		end
	end
	local conns = {
		RunService.Heartbeat:Connect(rec("Heartbeat")),
		RunService.PostSimulation:Connect(rec("PostSimulation")),
		RunService.Stepped:Connect(rec("Stepped")),
		RunService.PreSimulation:Connect(rec("PreSimulation")),
		RunService.PreAnimation:Connect(rec("PreAnimation")),
		RunService.RenderStepped:Connect(rec("RenderStepped")),
		RunService.PreRender:Connect(rec("PreRender")),
	}
	RunService:BindToRenderStep("late", Enum.RenderPriority.Character.Value, rec("bind300"))
	RunService:BindToRenderStep("early", Enum.RenderPriority.Input.Value, rec("bind100"))
	RunService:BindToRenderStep("cam", Enum.RenderPriority.Camera.Value + 1, rec("bind201"))
	task.spawn(function()
		task.wait()
		table.insert(seq, "wait")
	end)
	MOCK.step(1 / 60)
	local want = "bind100,bind201,bind300,PreRender,RenderStepped,PreAnimation,PreSimulation,Stepped,PostSimulation,Heartbeat,wait"
	check("frame phase order", table.concat(seq, ",") == want, table.concat(seq, ","))
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	for _, n in ipairs({ "late", "early", "cam" }) do
		RunService:UnbindFromRenderStep(n)
	end
	check("bindings removed", #MOCK.renderBindings() == 0)
	check("BindToRenderStep needs a number priority", (errors(function()
		RunService:BindToRenderStep("x", Enum.RenderPriority.Camera, function() end)
	end)))
end

---------------------------------------------------------------- tweens
do
	local v = Instance.new("NumberValue")
	local tw = TweenService:Create(v, TweenInfo.new(1, Enum.EasingStyle.Linear), { Value = 1 })
	local completed = {}
	tw.Completed:Connect(function(state)
		table.insert(completed, state)
	end)
	tw:Play()
	check("tween playing", tw.PlaybackState == Enum.PlaybackState.Playing)
	MOCK.run(0.5)
	check("linear tween at 0.5 s", near(v.Value, 0.5, 1e-6), v.Value)
	MOCK.run(0.6)
	check("tween completes exactly", v.Value == 1 and #completed == 1 and completed[1] == Enum.PlaybackState.Completed)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	TweenService:Create(f, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = Color3.new(1, 1, 1), Position = UDim2.fromScale(1, 0) }):Play()
	MOCK.run(0.5)
	check("quad out color", near(f.BackgroundColor3, Color3.new(0.75, 0.75, 0.75), 1e-6), f.BackgroundColor3)
	check("UDim2 tween", near(f.Position.X.Scale, 0.75, 1e-6))
	-- a newer tween on the same property cancels the older one
	local n = Instance.new("NumberValue")
	local t1 = TweenService:Create(n, TweenInfo.new(1), { Value = 10 })
	local t1state
	t1.Completed:Connect(function(s)
		t1state = s
	end)
	t1:Play()
	MOCK.step()
	TweenService:Create(n, TweenInfo.new(0.1), { Value = -1 }):Play()
	check("conflicting tween cancels", t1.PlaybackState == Enum.PlaybackState.Cancelled and t1state == Enum.PlaybackState.Cancelled)
	MOCK.run(0.2)
	check("newer tween wins", n.Value == -1)
	local d = Instance.new("NumberValue")
	TweenService:Create(d, TweenInfo.new(0.2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, true, 0.5), { Value = 1 }):Play()
	MOCK.run(0.4)
	check("DelayTime", d.Value == 0)
	MOCK.run(0.3)
	check("reverses peak", d.Value > 0.9, d.Value)
	MOCK.run(0.3)
	check("reverses back to start", d.Value == 0, d.Value)
	check("tween type mismatch errors", (errors(function()
		TweenService:Create(Instance.new("Frame"), TweenInfo.new(), { Size = 5 })
	end, "type mismatch")))
	check("tween unknown property errors", (errors(function()
		TweenService:Create(Instance.new("Frame"), TweenInfo.new(), { Sizee = UDim2.new() })
	end, "no property")))
	check("GetValue", near(TweenService:GetValue(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), 0.25, 1e-9))
	check("tweens done", MOCK.activeTweenCount() == 0)
end

---------------------------------------------------------------- client: character, joints, animator
local player = MOCK.setupClient({ spawn = CFrame.new(10, MOCK.groundY + 3, -20) * CFrame.Angles(0, 0.5, 0) })
local char = player.Character
local hrp = char.HumanoidRootPart
local humanoid = char.Humanoid
do
	check("LocalPlayer", Players.LocalPlayer == player and player.UserId == 1)
	check("RunService client", RunService:IsClient() and not RunService:IsServer() and RunService:IsRunning())
	check("character not archivable", char.Archivable == false and char:Clone() == nil)
	check("humanoid", humanoid.RigType == Enum.HumanoidRigType.R15 and humanoid.HipHeight == 2 and humanoid.RootPart == hrp)
	check("PlayerScripts.PlayerModule", player.PlayerScripts:FindFirstChild("PlayerModule") ~= nil and player:FindFirstChild("PlayerGui") ~= nil)
	local waist = char.UpperTorso:FindFirstChild("Waist")
	check("Waist in UpperTorso", waist and waist:IsA("Motor6D") and waist.Part0 == char.LowerTorso and waist.Part1 == char.UpperTorso)
	local root = char.LowerTorso:FindFirstChild("Root")
	check("Root in LowerTorso", root and root.Part0 == hrp)
	local n = 0
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") then
			n += 1
			check("motor " .. d.Name .. " lives in Part1", d.Parent == d.Part1)
		end
	end
	check("15 Motor6Ds", n == 15, n)
	-- rest pose: every part at its §4.1 centre
	MOCK.solveJoints(char)
	for _, pd in ipairs(MOCK.R15.parts) do
		local p = char[pd[1]]
		check("rest " .. pd[1], near(p.CFrame, hrp.CFrame * CFrame.new(pd[3]), 1e-6), p.Position)
	end
	-- a joint rotates its part about the §4.1 pivot
	local function pivotRot(name, partName, rot)
		local pivot, centre
		for _, jd in ipairs(MOCK.R15.joints) do
			if jd[1] == name then
				pivot = jd[4]
			end
		end
		for _, pd in ipairs(MOCK.R15.parts) do
			if pd[1] == partName then
				centre = pd[3]
			end
		end
		return CFrame.new(pivot) * rot * CFrame.new(centre - pivot)
	end
	local rot = CFrame.Angles(0.4, 0.2, -0.3)
	char.UpperTorso.Waist.Transform = rot
	MOCK.solveJoints(char)
	check("Waist rotates UpperTorso about its pivot", near(char.UpperTorso.CFrame, hrp.CFrame * pivotRot("Waist", "UpperTorso", rot), 1e-6))
	-- chain: Waist moves the arm too
	local shoulderPivot = Vector3.new(1.25, 1.1, 0)
	local waistPivot = Vector3.new(0, -0.3, 0)
	local handCentre = Vector3.new(1.5, -1.15, 0)
	local want = hrp.CFrame * CFrame.new(waistPivot) * rot * CFrame.new(handCentre - waistPivot)
	check("chain moves RightHand", near(char.RightHand.CFrame, want, 1e-6))
	char.UpperTorso.Waist.Transform = CFrame.identity
	local srot = CFrame.Angles(0, 0, 1.2)
	char.RightUpperArm.RightShoulder.Transform = srot
	MOCK.solveJoints(char)
	want = hrp.CFrame * CFrame.new(shoulderPivot) * srot * CFrame.new(handCentre - shoulderPivot)
	check("RightShoulder swings the hand", near(char.RightHand.CFrame, want, 1e-6))
	char.RightUpperArm.RightShoulder.Transform = CFrame.identity
	MOCK.solveJoints(char)
	-- the accessory weld (Part0 = Handle, Part1 = Head) is solved backwards
	check("accessory follows head", near(char.MockHat.Handle.Position, char.Head.CFrame * Vector3.new(0, 0.8, 0), 1e-6))
	-- grip attachment like Roblox (DESIGN §4.3)
	check("RightGripAttachment", near(char.RightHand.RightGripAttachment.CFrame, CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0), 1e-9))
	check("attachment world cframe", near(char.RightHand.RightGripAttachment.WorldCFrame, char.RightHand.CFrame * char.RightHand.RightGripAttachment.CFrame, 1e-9))
	-- R6
	local r6 = MOCK.makeCharacter("R6", "R6Dummy")
	r6:PivotTo(CFrame.new(0, 50, 0))
	r6.Parent = workspace
	MOCK.solveJoints(r6)
	local base = r6.HumanoidRootPart.CFrame
	check("R6 Right Arm", near(r6["Right Arm"].CFrame, base * CFrame.new(1.5, 0, 0), 1e-6))
	check("R6 Left Leg", near(r6["Left Leg"].CFrame, base * CFrame.new(-0.5, -2, 0), 1e-6))
	check("R6 Head", near(r6.Head.CFrame, base * CFrame.new(0, 1.5, 0), 1e-6))
	check("R6 joints in Torso", r6.Torso:FindFirstChild("Right Shoulder") and r6.HumanoidRootPart:FindFirstChild("RootJoint"))
	r6:Destroy()
	-- clones remap joint references; ViewportFrames only solve inside a WorldModel
	char.Archivable = true
	local clone = char:Clone()
	char.Archivable = false
	check("clone remaps Part0/Part1", clone.UpperTorso.Waist.Part0 == clone.LowerTorso and clone.PrimaryPart == clone.HumanoidRootPart)
	local gui = Instance.new("ScreenGui")
	gui.Parent = player.PlayerGui
	local vpf = Instance.new("ViewportFrame")
	vpf.Parent = gui
	clone.Parent = vpf
	local before = clone.UpperTorso.CFrame
	clone.HumanoidRootPart.CFrame = CFrame.new(0, 100, 0)
	MOCK.step()
	check("no joint solving in a bare ViewportFrame", clone.UpperTorso.CFrame == before)
	local wm = Instance.new("WorldModel")
	wm.Parent = vpf
	clone.Parent = wm
	MOCK.step()
	check("WorldModel solves joints", near(clone.UpperTorso.Position, Vector3.new(0, 100.5, 0), 1e-6))
	gui:Destroy()
end

do
	-- Animator: the idle track from the Animate script writes Transform each frame
	local animator = humanoid.Animator
	check("idle track playing", #animator:GetPlayingAnimationTracks() == 1)
	local waist = char.UpperTorso.Waist
	local mine = CFrame.Angles(0, 1, 0)
	local c1 = RunService.RenderStepped:Connect(function()
		waist.Transform = mine
	end)
	MOCK.step()
	check("Animator overwrites RenderStepped writes", waist.Transform ~= mine)
	c1:Disconnect()
	local c2 = RunService.PreSimulation:Connect(function()
		waist.Transform = mine
	end)
	MOCK.step()
	check("PreSimulation writes survive the Animator", waist.Transform == mine)
	local want = char.LowerTorso.CFrame * waist.C0 * mine * waist.C1:Inverse()
	check("solver used the PreSimulation Transform", near(char.UpperTorso.CFrame, want, 1e-6))
	c2:Disconnect()
	local animate = char.Animate
	animate.Enabled = false
	check("Disabled mirrors Enabled", animate.Disabled == true)
	for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
		t:Stop(0)
	end
	MOCK.step()
	check("stopped tracks", #animator:GetPlayingAnimationTracks() == 0)
	waist.Transform = mine
	MOCK.run(0.2)
	check("no tracks: Animator leaves joints alone", waist.Transform == mine)
	waist.Transform = CFrame.identity
	animate.Enabled = true
	check("re-enabling Animate restarts idle", #animator:GetPlayingAnimationTracks() == 1)
	-- controls
	local controls = mockRequire(player.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
	controls:Disable()
	check("controls disabled", MOCK.controlsEnabled == false)
	controls:Enable()
	check("controls enabled", MOCK.controlsEnabled == true)
	check("unknown control member errors", (errors(function()
		return controls.Frobnicate
	end)))
	-- humanoid state
	humanoid.PlatformStand = true
	check("PlatformStand state", humanoid:GetState() == Enum.HumanoidStateType.PlatformStanding)
	humanoid.PlatformStand = false
	check("back to running", humanoid:GetState() == Enum.HumanoidStateType.Running)
end

---------------------------------------------------------------- camera, raycast, GUI
do
	local cam = workspace.CurrentCamera
	check("camera custom on spawn", cam.CameraType == Enum.CameraType.Custom and cam.CameraSubject == humanoid)
	MOCK.step()
	local focus = hrp.Position + Vector3.new(0, 1.5, 0)
	check("default camera follows the character", near((cam.CFrame.Position - focus).Magnitude, MOCK.cameraZoom, 1e-6) and near(cam.CFrame.LookVector, (focus - cam.CFrame.Position).Unit, 1e-6))
	cam.CameraType = Enum.CameraType.Scriptable
	local fixed = CFrame.new(0, 200, 0) * CFrame.Angles(-1, 0, 0)
	cam.CFrame = fixed
	MOCK.step()
	check("Scriptable camera is left alone", cam.CFrame == fixed)
	local ray = cam:ViewportPointToRay(640, 360)
	check("viewport centre ray", near(ray.Direction, fixed.LookVector, 1e-9))
	local sp, onScreen = cam:WorldToViewportPoint(fixed.Position + fixed.LookVector * 50)
	check("WorldToViewportPoint centre", onScreen and near(sp.X, 640, 1e-6) and near(sp.Y, 360, 1e-6) and near(sp.Z, 50, 1e-6))
	cam.CameraType = Enum.CameraType.Custom

	local down = Vector3.new(0, -500, 0)
	local top = hrp.Position + Vector3.new(0, 200, 0)
	local hit = workspace:Raycast(top, down)
	check("ray hits the character first", hit and hit.Instance:IsDescendantOf(char), hit and hit.Instance:GetFullName())
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	hit = workspace:Raycast(top, down, params)
	check("excluded character: ground", hit and hit.Instance == workspace.Terrain and near(hit.Position.Y, MOCK.groundY, 1e-9) and hit.Normal == Vector3.yAxis)
	check("RaycastParams strict", (errors(function()
		params.FilterDescendantInstances = {}
	end)))
	check("filter needs instances", (errors(function()
		params.FilterDescendantsInstances = { "x" }
	end)))
	local inc = RaycastParams.new()
	inc.FilterType = Enum.RaycastFilterType.Include
	inc.FilterDescendantsInstances = { char }
	check("include list without terrain misses ground", workspace:Raycast(Vector3.new(500, 100, 500), down, inc) == nil)
	MOCK.raycastHook = function(origin)
		if origin.X == 1234 then
			return MOCK.raycastResult(workspace.Terrain, Vector3.new(1234, 7, 0), Vector3.yAxis, Enum.Material.Rock, 1)
		end
		return nil
	end
	check("raycast hook", workspace:Raycast(Vector3.new(1234, 100, 0), down).Position.Y == 7)
	MOCK.raycastHook = nil

	local gui = Instance.new("ScreenGui")
	gui.IgnoreGuiInset = true
	gui.Parent = player.PlayerGui
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 0.1)
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Parent = gui
	check("AbsoluteSize", bar.AbsoluteSize == Vector2.new(1280, 72))
	check("AbsolutePosition", bar.AbsolutePosition == Vector2.new(0, 648))
	gui.IgnoreGuiInset = false
	check("gui inset", near(bar.AbsoluteSize.Y, (720 - 58) * 0.1, 1e-9))
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Rotation = 90
	g.Parent = bar
	check("UIGradient", g.Rotation == 90 and #g.Transparency.Keypoints == 3)
	local vpf = Instance.new("ViewportFrame")
	vpf.Ambient = Color3.new(0, 0, 0)
	vpf.CurrentCamera = Instance.new("Camera")
	check("ViewportFrame camera must be a Camera", (errors(function()
		vpf.CurrentCamera = Instance.new("Part")
	end)))
	gui:Destroy()
end

---------------------------------------------------------------- lighting, sound, remotes, tools, input
do
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 6
	check("TimeOfDay follows ClockTime", Lighting.TimeOfDay == "06:00:00")
	Lighting.TimeOfDay = "18:30:00"
	check("ClockTime follows TimeOfDay", near(Lighting.ClockTime, 18.5, 1e-9))
	check("sun direction unit", near(Lighting:GetSunDirection().Magnitude, 1, 1e-9))
	check("Lighting.Technology is not scriptable at runtime", (errors(function()
		Lighting.Technology = Enum.Technology.Future
	end, "lacking capability")))
	local tiny = Instance.new("Part")
	tiny.Size = Vector3.new(0, 1, 1)
	check("tiny part sizes clamp to 0.001", tiny.Size.X == 0.001)
	local cc = Instance.new("ColorCorrectionEffect")
	check("post effect defaults", cc.Enabled and cc.TintColor == Color3.new(1, 1, 1))

	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://1"
	s.Parent = workspace
	local ended = false
	s.Ended:Connect(function()
		ended = true
	end)
	s:Play()
	check("sound playing", s.IsPlaying)
	MOCK.run(2.1)
	check("sound ended", ended and not s.IsPlaying)
	s:Destroy()

	-- remotes: server code runs in the server context
	local re = Instance.new("RemoteEvent")
	re.Name = "TestRemote"
	re.Parent = ReplicatedStorage
	local got
	MOCK.runInContext("server", function()
		check("server context", RunService:IsServer() and not RunService:IsClient() and Players.LocalPlayer == nil)
		re.OnServerEvent:Connect(function(plr, c)
			got = { plr, c, RunService:IsServer() }
		end)
	end)
	check("OnServerEvent can't be used on the client", (errors(function()
		re.OnServerEvent:Connect(function() end)
	end)))
	re:FireServer(Color3.new(1, 0, 0))
	check("remote delivery is not synchronous", got == nil)
	MOCK.step()
	check("FireServer delivered with player", got and got[1] == player and got[2] == Color3.new(1, 0, 0) and got[3] == true)
	MOCK.runInContext("server", function()
		check("FireServer from the server errors", (errors(function()
			re:FireServer()
		end)))
	end)
	re:Destroy()

	-- tools: equipping welds the handle to the hand with the grip
	local tool = Instance.new("Tool")
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 4, 0.5)
	handle.Parent = tool
	tool.Grip = CFrame.new(0, -1, 0)
	tool.Parent = player.Backpack
	humanoid:EquipTool(tool)
	local grip = char.RightHand:FindFirstChild("RightGrip")
	check("RightGrip weld", grip and grip.Part0 == char.RightHand and grip.Part1 == handle)
	MOCK.step()
	local want = char.RightHand.CFrame * char.RightHand.RightGripAttachment.CFrame * tool.Grip:Inverse()
	check("tool held at the grip", near(handle.CFrame, want, 1e-6))
	humanoid:UnequipTools()
	check("unequip", tool.Parent == player.Backpack and char.RightHand:FindFirstChild("RightGrip") == nil)
	tool:Destroy()

	-- input
	local fired, uisFired = 0, nil
	ContextActionService:BindAction("Test", function(_, state)
		if state == Enum.UserInputState.Begin then
			fired += 1
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F7)
	local c = UserInputService.InputBegan:Connect(function(io, gp)
		uisFired = io.KeyCode
	end)
	MOCK.tapKey(Enum.KeyCode.F7)
	check("CAS action", fired == 1)
	check("InputBegan", uisFired == Enum.KeyCode.F7)
	ContextActionService:UnbindAction("Test")
	c:Disconnect()
	MOCK.tapKey(Enum.KeyCode.F7)
	check("unbound", fired == 1 and #MOCK.boundActions() == 0)

	local ok = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
	check("SetCoreGuiEnabled", ok and StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack) == false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	check("SetCore unknown errors", (errors(function()
		StarterGui:SetCore("NotAThing", 1)
	end)))
	check("RequestStreamAroundAsync", pcall(function()
		player:RequestStreamAroundAsync(Vector3.new(1, 2, 3))
	end) and #MOCK.streamRequests == 1)
	local hl = Instance.new("Highlight")
	check("Highlight", hl.DepthMode == Enum.HighlightDepthMode.AlwaysOnTop and hl.FillTransparency == 0.5)
end

---------------------------------------------------------------- summary
for msg, n in pairs(MOCK.warnings) do
	print(string.format("MOCKWARN x%d %s", n, msg))
end
check("no unexpected mock warnings", next(MOCK.warnings) == nil)
check("no thread errors", #MOCK.errors == 0, #MOCK.errors)
if failures == 0 then
	print(string.format("SELFTEST OK (%d checks)", checks))
else
	print(string.format("SELFTEST FAILED %d of %d checks", failures, checks))
	error("selftest failed")
end
