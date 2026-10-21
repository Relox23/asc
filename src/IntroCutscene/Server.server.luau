--[[
	Server  (Script, RunContext = Server; runs where it is, inside ReplicatedStorage.IntroCutscene)
	The server side of the intro cutscene (docs/intro/DESIGN.md §7.0):

	  * creates the RemoteEvent ReplicatedStorage.IntroCutscene_Finished that the client fires
	    with the soul core colour when the cutscene ends
	  * when Config.GIVE_SWORD is true, gives that player the ResonanceSword: a Tool built from the
	    ResonanceSword pieces of ReplicatedStorage.IntroAssets (or the part-built stand-in when
	    the meshes aren't imported), crystals tinted Neon in the colour, put in the Backpack (and
	    StarterGear, so it comes back after a respawn) and equipped

	Nothing but the colour comes from the client, and the colour is checked: it must be a Color3
	with finite components (clamped to 0..1). Requests are rate limited, and every player gets
	the sword at most once per server (a player who already has a ResonanceSword gets nothing).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local package = script.Parent
local Config = require(package:WaitForChild("Config"))
local Assets = require(package:WaitForChild("Assets"))

local REMOTE_NAME = "IntroCutscene_Finished"
local TOOL_NAME = "ResonanceSword"
local MIN_INTERVAL = 2 -- seconds between two requests of one player that are looked at

local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if not (remote and remote:IsA("RemoteEvent")) then
	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
end

local lastRequest = {} -- [Player] = os.clock() of the last request looked at
local given = {} -- [Player] = true once the sword was given

local function validColor(value)
	local valueType = typeof(value)
	if valueType ~= "Color3" then
		return nil
	end
	local r, g, b = value.R, value.G, value.B
	for _, c in ipairs({ r, g, b }) do
		if type(c) ~= "number" or c ~= c or c == math.huge or c == -math.huge then
			return nil
		end
	end
	return Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
end

local function hasSword(player)
	for _, holder in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character, player:FindFirstChildOfClass("StarterGear") }) do
		local tool = holder and holder:FindFirstChild(TOOL_NAME)
		if tool and tool:IsA("Tool") then
			return true
		end
	end
	return false
end

-- The Tool: an invisible Handle at the grip centre (blade along its +Y, so the default Grip holds
-- it like the cutscene's hand does, DESIGN §4.3) with every sword piece welded to it.
local function buildSword(color)
	local model = Assets.place(TOOL_NAME, nil, CFrame.new())
	Assets.setResonance(model, color, 1)
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.ToolTip = "Resonance Sword"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.identity
	tool:SetAttribute("SoulColor", color)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 1.1, 0.3)
	handle.CFrame = model:GetPivot()
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Anchored = false
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	for _, p in ipairs(Assets.pieces(model)) do
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		local weld = Instance.new("Weld")
		weld.Name = "Weld_" .. p.Name
		weld.Part0 = handle
		weld.Part1 = p
		weld.C0 = handle.CFrame:ToObjectSpace(p.CFrame)
		weld.C1 = CFrame.identity
		weld.Parent = p
		p.Parent = tool
	end
	-- crystals glow a little in the dark
	local crystal = Assets.pieces(tool, "Crystal")[1]
	if crystal then
		local glow = Instance.new("PointLight")
		glow.Name = "ResonanceGlow"
		glow.Color = color
		glow.Brightness = 0.8
		glow.Range = 7
		glow.Shadows = false
		glow.Parent = crystal
	end
	model:Destroy()
	return tool
end

local function giveSword(player, color)
	if hasSword(player) then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack or player.Parent ~= Players then
		return
	end
	local tool = buildSword(color)
	local gear = player:FindFirstChildOfClass("StarterGear")
	if gear then
		tool:Clone().Parent = gear
	end
	tool.Parent = backpack
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:EquipTool(tool)
	end
end

remote.OnServerEvent:Connect(function(player, value)
	local now = os.clock()
	local last = lastRequest[player]
	if last and now - last < MIN_INTERVAL then
		return
	end
	lastRequest[player] = now
	if given[player] then
		return
	end
	local color = validColor(value)
	if not color then
		return
	end
	given[player] = true
	if Config.GIVE_SWORD == false then
		return
	end
	local ok, err = pcall(giveSword, player, color)
	if not ok then
		warn("[IntroCutscene] could not give the sword to " .. player.Name .. ": " .. tostring(err))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
	given[player] = nil
end)
