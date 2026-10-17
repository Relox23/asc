-- Tests placing an imported watchtower mesh (fixture boxes from the real OBJ).
local Gen = mockRequire(GENERATOR)
local Landscape = mockRequire(GENERATOR.Landscape)
local Layout = mockRequire(GENERATOR.IslandLayout)
local Watchtower = mockRequire(GENERATOR.Watchtower)
Landscape.init()

local function makeFixture(rotation)
	local m = Instance.new("Model")
	m.Name = "PleiadesWatchtower"
	for _, f in ipairs(IMPORT_FIXTURE) do
		local p = Instance.new("MeshPart")
		p.Name = f.name
		p.Size = f.size
		p.CFrame = rotation * CFrame.new(f.center + Vector3.new(30, 5, -12))
		p.Parent = m
	end
	m.Parent = game:GetService("ServerStorage")
	return m
end

local function check(label, rotation)
	local old = game:GetService("ServerStorage"):FindFirstChild("PleiadesWatchtower")
	if old then
		old:Destroy()
	end
	makeFixture(rotation)
	Gen.Build({ "Dunes" })
	local tower = workspace.Island.Dunes:FindFirstChild("PleiadesWatchtower")
	local g = Landscape.WatchtowerHeight
	local base = Vector3.new(Layout.Landmarks.Watchtower.X, g, Layout.Landmarks.Watchtower.Z)
	local lo, hi = Vector3.new(1e9, 1e9, 1e9), Vector3.new(-1e9, -1e9, -1e9)
	local body, porch
	for _, p in ipairs(tower:GetDescendants()) do
		if p:IsA("BasePart") then
			lo = lo:Min(p.Position - p.Size / 2)
			hi = hi:Max(p.Position + p.Size / 2)
			if p.Name == "Stone_Body" then
				body = p
			elseif p.Name == "Stone_Portico" then
				porch = p
			end
			assert(p.Anchored, "imported part not anchored")
		end
	end
	local toCenter = Vector3.new(-base.X, 0, -base.Z).Unit
	local facing = Vector3.new(porch.Position.X - body.Position.X, 0, porch.Position.Z - body.Position.Z).Unit
	print(string.format("%s: height=%.1f bottom=%.1f (want %.1f) crownTop=%.1f (want %.1f) axisOffset=%.2f facingDot=%.3f color=%s",
		label, hi.Y - lo.Y, lo.Y, g - 22, body.Position.Y + body.Size.Y / 2, g + 704,
		(Vector3.new(body.Position.X, 0, body.Position.Z) - Vector3.new(base.X, 0, base.Z)).Magnitude,
		facing:Dot(toCenter), tostring(body.Material)))
end

check("as exported (Y up)", CFrame.new())
check("imported lying down (Z up)", CFrame.Angles(math.pi / 2, 0, 0))
check("imported upside down", CFrame.Angles(math.pi, 0, 0))
check("imported turned sideways (X up)", CFrame.Angles(0, 0, math.pi / 2))
