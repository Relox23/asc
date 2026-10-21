--[[
	CharacterRig
	Puts the player's real avatar into the cutscene (DESIGN §4, §7.2).

	    local rig = CharacterRig.new(player, character, folder)   -- folder holds the glow Highlight
	    rig:Takeover()           anchor the HumanoidRootPart, stop/block animations (Animate script
	                             off, playing tracks stopped, new ones stopped at once), controls off,
	                             tools unequipped, AutoRotate / state machine off
	    rig:SetColor(color)      soul core colour (light form glow)
	    rig:Update(t, cs, origin) cs = Timeline:character(t), origin = world stage CFrame:
	                             HRP CFrame, every Motor6D.Transform, visibility (`visible`) and
	                             form (`form`: 0 light -> 1 solid body); forward kinematics cached
	    rig:ApplyJoints()        re-applies this frame's Transforms; connected to
	                             RunService.PreSimulation (after the Animator) by init
	    rig:PartCFrame(part)     -> CFrame  where a character part is this frame (FK, exact even
	                             before the engine has solved the joints); part.CFrame otherwise
	    rig:GripCF()             -> CFrame  sword pivot in the right hand (§4.3)
	    rig:RootCF(cs, origin)   -> CFrame  HRP CFrame for a character sample (height offset incl.)
	    rig:SetHidden(hidden)    force hidden (true) / back to the data (false)
	    rig:IsAlive()            -> boolean
	    rig:Restore(finalCF?)    undo everything; with finalCF the character is left standing
	                             there (upright, unanchored)
	    rig.character, rig.humanoid, rig.root, rig.isR15, rig.animated, rig.heightOffset

	Bone axes are Roblox joint axes (§4.2), so a joint quaternion is the Motor6D
	Transform as is. Avatars of other sizes are lifted by
	(HipHeight + HRP.Size.Y / 2) - 3 along the stage's up so the feet land where
	the mannequin's do (§4.4). The game is R15 only: an R6 character is moved and
	hidden/shown like the root but not animated.
]]

local Convert = require(script.Parent.Convert)

local CharacterRig = {}
CharacterRig.__index = CharacterRig

local IDENTITY = CFrame.identity
local WHITE = Color3.new(1, 1, 1)

-- R15 Motor6Ds, parents first: { joint (= Motor6D name), part it moves (Part1), part it hangs on (Part0) }
local JOINTS = {
	{ "Root", "LowerTorso", "HumanoidRootPart" },
	{ "Waist", "UpperTorso", "LowerTorso" },
	{ "Neck", "Head", "UpperTorso" },
	{ "LeftShoulder", "LeftUpperArm", "UpperTorso" },
	{ "LeftElbow", "LeftLowerArm", "LeftUpperArm" },
	{ "LeftWrist", "LeftHand", "LeftLowerArm" },
	{ "RightShoulder", "RightUpperArm", "UpperTorso" },
	{ "RightElbow", "RightLowerArm", "RightUpperArm" },
	{ "RightWrist", "RightHand", "RightLowerArm" },
	{ "LeftHip", "LeftUpperLeg", "LowerTorso" },
	{ "LeftKnee", "LeftLowerLeg", "LeftUpperLeg" },
	{ "LeftAnkle", "LeftFoot", "LeftLowerLeg" },
	{ "RightHip", "RightUpperLeg", "LowerTorso" },
	{ "RightKnee", "RightLowerLeg", "RightUpperLeg" },
	{ "RightAnkle", "RightFoot", "RightLowerLeg" },
}
CharacterRig.JOINTS = JOINTS

local function findMotor(character, jointName, partName)
	local part = character:FindFirstChild(partName)
	local m = part and part:FindFirstChild(jointName)
	if m and m:IsA("Motor6D") then
		return m
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name == jointName then
			return d
		end
	end
	return nil
end

function CharacterRig.new(player, character, folder)
	local self = setmetatable({}, CharacterRig)
	self.player = player
	self.character = character
	self.folder = folder
	self.humanoid = character:FindFirstChildOfClass("Humanoid")
	assert(self.humanoid, "character has no Humanoid")
	self.root = character:FindFirstChild("HumanoidRootPart") or self.humanoid.RootPart
	assert(self.root, "character has no HumanoidRootPart")
	self.isR15 = self.humanoid.RigType == Enum.HumanoidRigType.R15
	self.color = WHITE
	self.active = false
	self.hidden = false
	self.connections = {}
	self.partCF = {}
	self.joints = {}
	self.attached = {}
	self.visuals = {}
	self.saved = {}
	if self.isR15 then
		for _, spec in ipairs(JOINTS) do
			local motor = findMotor(character, spec[1], spec[2])
			if motor and motor.Part0 and motor.Part1 then
				table.insert(self.joints, {
					name = spec[1],
					motor = motor,
					part0 = motor.Part0,
					part1 = motor.Part1,
					c0 = motor.C0,
					c1inv = motor.C1:Inverse(),
					transform = nil,
				})
			end
		end
	end
	self.animated = #self.joints > 0
	if self.isR15 then
		self.heightOffset = self.humanoid.HipHeight + self.root.Size.Y / 2 - 3.0
	else
		self.heightOffset = 0 -- an R6 root already sits 3 studs above the feet
	end
	return self
end

function CharacterRig:IsAlive()
	local hum = self.humanoid
	return hum ~= nil and hum.Parent ~= nil and hum.Health > 0 and self.root.Parent ~= nil and self.character:IsDescendantOf(workspace)
end

function CharacterRig:_controls()
	if self.controls == nil then
		self.controls = false
		pcall(function()
			local playerScripts = self.player:FindFirstChild("PlayerScripts") or self.player:WaitForChild("PlayerScripts", 5)
			local module = playerScripts and playerScripts:WaitForChild("PlayerModule", 5)
			if module then
				self.controls = require(module):GetControls()
			end
		end)
	end
	return self.controls or nil
end

-- Parts welded to a body part (accessory handles, ...) keep their offset from it.
function CharacterRig:_collectAttached()
	local body = {}
	body[self.root] = true
	for _, j in ipairs(self.joints) do
		body[j.part0] = true
		body[j.part1] = true
	end
	for _, d in ipairs(self.character:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			local a, b = d.Part0, d.Part1
			local part, base
			if a and b then
				if body[a] and not body[b] then
					part, base = b, a
				elseif body[b] and not body[a] then
					part, base = a, b
				end
			end
			if part and base and part:IsDescendantOf(self.character) then
				table.insert(self.attached, { part = part, base = base, offset = base.CFrame:ToObjectSpace(part.CFrame) })
			end
		end
	end
end

function CharacterRig:Takeover()
	if self.active then
		return
	end
	self.active = true
	local hum, root, character, saved = self.humanoid, self.root, self.character, self.saved

	pcall(function()
		hum:UnequipTools()
	end)
	if hum.Sit then
		pcall(function()
			hum.Sit = false
		end)
	end

	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("BaseScript") then
		saved.animate = animate
		saved.animateEnabled = animate.Enabled
		animate.Enabled = false
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
		table.insert(
			self.connections,
			animator.AnimationPlayed:Connect(function(track)
				if self.active then
					track:Stop(0)
				end
			end)
		)
	end

	saved.autoRotate = hum.AutoRotate
	hum.AutoRotate = false
	pcall(function()
		saved.evaluateStateMachine = hum.EvaluateStateMachine
		hum.EvaluateStateMachine = false
	end)
	saved.anchored = root.Anchored
	root.Anchored = true
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)

	self:_collectAttached()
	for _, d in ipairs(character:GetDescendants()) do
		if (d:IsA("BasePart") and d ~= root) or d:IsA("Decal") then
			table.insert(self.visuals, { d, d.LocalTransparencyModifier })
		end
	end

	local controls = self:_controls()
	if controls then
		pcall(function()
			controls:Disable()
		end)
	end

	local hl = Instance.new("Highlight")
	hl.Name = "IntroFormGlow"
	hl.Adornee = character
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillTransparency = 1
	hl.OutlineTransparency = 1
	hl.Enabled = false
	hl.Parent = self.folder or character
	self.highlight = hl
end

function CharacterRig:SetColor(color)
	self.color = color or WHITE
end

function CharacterRig:SetHidden(hidden)
	self.hidden = hidden and true or false
end

function CharacterRig:RootCF(cs, origin)
	return origin * CFrame.new(0, self.heightOffset, 0) * Convert.localCF(cs.root.pos, cs.root.rot)
end

function CharacterRig:_setLook(visible, form)
	local ltm = visible and (1 - form) * 0.75 or 1
	for _, v in ipairs(self.visuals) do
		v[1].LocalTransparencyModifier = ltm
	end
	local hl = self.highlight
	if hl then
		local glow = visible and form < 0.999
		hl.Enabled = glow
		if glow then
			hl.FillColor = self.color
			hl.FillTransparency = 0.1 + 0.9 * form
			hl.OutlineColor = self.color:Lerp(WHITE, 0.5)
			hl.OutlineTransparency = 0.2 + 0.8 * form
		end
	end
end

function CharacterRig:Update(t, cs, origin)
	if not self.active or not cs then
		return
	end
	local channels = cs.channels
	local visible = channels.visible
	if visible == nil then
		visible = 1
	end
	if t < cs.t0 - 1e-6 or self.hidden then
		visible = 0
	end
	local form = channels.form or 1

	local rootCF = self:RootCF(cs, origin)
	self.rootCF = rootCF
	self.root.CFrame = rootCF

	if self.animated then
		local partCF = self.partCF
		partCF[self.root] = rootCF
		local joints = cs.joints
		for _, j in ipairs(self.joints) do
			local q = joints[j.name]
			local tr = IDENTITY
			if q then
				tr = j.name == "Root" and Convert.jointCF(q, cs.rootLoc) or Convert.jointCF(q)
			end
			j.transform = tr
			j.motor.Transform = tr
			partCF[j.part1] = (partCF[j.part0] or j.part0.CFrame) * j.c0 * tr * j.c1inv
		end
		for _, a in ipairs(self.attached) do
			partCF[a.part] = (partCF[a.base] or a.base.CFrame) * a.offset
		end
	end
	self:_setLook(visible >= 0.5, form)
end

function CharacterRig:ApplyJoints()
	if not self.active then
		return
	end
	for _, j in ipairs(self.joints) do
		local tr = j.transform
		if tr then
			j.motor.Transform = tr
		end
	end
end

function CharacterRig:PartCFrame(part)
	return self.partCF[part] or part.CFrame
end

function CharacterRig:GripCF()
	local hand = self.character:FindFirstChild("RightHand")
	if hand then
		return Convert.grip(self:PartCFrame(hand))
	end
	local arm = self.character:FindFirstChild("Right Arm") -- R6
	if arm then
		return Convert.grip(self:PartCFrame(arm) * CFrame.new(0, -0.85, 0))
	end
	return Convert.grip(self.rootCF or self.root.CFrame)
end

function CharacterRig:Restore(finalCF)
	if not self.active then
		return
	end
	self.active = false
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	table.clear(self.connections)
	for _, j in ipairs(self.joints) do
		j.transform = nil
		pcall(function()
			j.motor.Transform = IDENTITY
		end)
	end
	for _, v in ipairs(self.visuals) do
		pcall(function()
			v[1].LocalTransparencyModifier = v[2]
		end)
	end
	table.clear(self.visuals)
	table.clear(self.attached)
	table.clear(self.partCF)
	if self.highlight then
		self.highlight:Destroy()
		self.highlight = nil
	end
	local hum, root, saved = self.humanoid, self.root, self.saved
	if finalCF and self:IsAlive() then
		-- upright, facing where the final pose faces
		local look = finalCF.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		local pos = finalCF.Position
		pcall(function()
			root.CFrame = flat.Magnitude > 1e-3 and CFrame.lookAt(pos, pos + flat) or CFrame.new(pos)
		end)
	end
	pcall(function()
		root.Anchored = saved.anchored or false
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	pcall(function()
		hum.AutoRotate = saved.autoRotate ~= false
	end)
	if saved.evaluateStateMachine ~= nil then
		pcall(function()
			hum.EvaluateStateMachine = saved.evaluateStateMachine
		end)
	end
	if saved.animate then
		pcall(function()
			saved.animate.Enabled = saved.animateEnabled
		end)
	end
	local controls = self:_controls()
	if controls then
		pcall(function()
			controls:Enable()
		end)
	end
end

return CharacterRig
