-- Runs the full generator against the mock and prints statistics.
local Gen = mockRequire(GENERATOR)
local t0 = os.clock()
Gen.Build()
print(string.format("MOCK build time %.1fs", os.clock() - t0))
local island = workspace:FindFirstChild("Island")
for _, folder in ipairs(island:GetChildren()) do
	local parts, models, lights, emitters = 0, 0, 0, 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Model") then
			models += 1
		elseif d:IsA("Light") then
			lights += 1
		elseif d:IsA("ParticleEmitter") then
			emitters += 1
		end
	end
	print(string.format("ZONE %-8s parts=%6d models=%5d lights=%4d emitters=%4d", folder.Name, parts, models, lights, emitters))
end
print(string.format("TOTAL parts alive=%d instances created=%d voxels=%d fills=%d", MOCK.partCount, MOCK.instanceCount, MOCK.voxelWrites, MOCK.fillCalls))
for msg, n in pairs(MOCK.warnings) do
	print(string.format("MOCKWARN x%d %s", n, msg))
end
local sps = game:GetService("StarterPlayer").StarterPlayerScripts
print("client script installed:", sps:FindFirstChild("IslandAtmosphere") ~= nil, "layout replicated:", game:GetService("ReplicatedStorage"):FindFirstChild("IslandLayout") ~= nil)

-- partial rebuild and clear
local before = MOCK.partCount
Gen.Build({ "Snow" })
print(string.format("rebuild Snow: parts before=%d after=%d", before, MOCK.partCount))
Gen.Clear()
print("after Clear: island exists =", workspace:FindFirstChild("Island") ~= nil, "parts alive =", MOCK.partCount)
