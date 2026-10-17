--!nocheck
-- Minimal Roblox API mock used to run the generator outside Studio.
-- It is strict about property names so typos fail here instead of in Studio.

local MOCK = { warnings = {}, partCount = 0, voxelWrites = 0, fillCalls = 0, instanceCount = 0 }


local function mockWarn(msg)
	MOCK.warnings[msg] = (MOCK.warnings[msg] or 0) + 1
end

---------------------------------------------------------------- Vector3
local V3 = {}
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return Vector3.new(0 / 0, 0 / 0, 0 / 0)
		end
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	elseif k == "x" or k == "y" or k == "z" then
		error("use uppercase Vector3 components", 2)
	end
	local m = V3[k]
	if m == nil then
		error("Vector3 has no member " .. tostring(k), 2)
	end
	return m
end
local function isV3(v)
	return type(v) == "table" and getmetatable(v) == V3
end
local function newV3(x, y, z)
	x, y, z = x or 0, y or 0, z or 0
	assert(type(x) == "number" and type(y) == "number" and type(z) == "number", "Vector3.new expects numbers")
	return setmetatable({ X = x, Y = y, Z = z }, V3)
end
V3.__add = function(a, b)
	assert(isV3(a) and isV3(b), "Vector3 + non-Vector3")
	return newV3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	assert(isV3(a) and isV3(b), "Vector3 - non-Vector3")
	return newV3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return newV3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return newV3(a.X * b, a.Y * b, a.Z * b)
	end
	assert(isV3(a) and isV3(b), "bad Vector3 multiply")
	return newV3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return newV3(a.X / b, a.Y / b, a.Z / b)
	end
	return newV3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__unm = function(a)
	return newV3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z)
end
function V3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3.Cross(a, b)
	return newV3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a, b, t)
	return a + (b - a) * t
end
function V3.Abs(a)
	return newV3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3.Max(a, b)
	return newV3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function V3.Min(a, b)
	return newV3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
Vector3 = {
	new = newV3,
	zero = newV3(0, 0, 0),
	one = newV3(1, 1, 1),
	xAxis = newV3(1, 0, 0),
	yAxis = newV3(0, 1, 0),
	zAxis = newV3(0, 0, 1),
}
MOCK.isV3 = isV3

Vector2 = {
	new = function(x, y)
		return { X = x or 0, Y = y or 0 }
	end,
}

---------------------------------------------------------------- CFrame
local CF = {}
local function newCFRaw(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	for _, n in ipairs({ x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }) do
		if n ~= n then
			error("CFrame has NaN component", 3)
		end
	end
	return setmetatable({
		x = x,
		y = y,
		z = z,
		r00 = r00,
		r01 = r01,
		r02 = r02,
		r10 = r10,
		r11 = r11,
		r12 = r12,
		r20 = r20,
		r21 = r21,
		r22 = r22,
	}, CF)
end
local function isCF(c)
	return type(c) == "table" and getmetatable(c) == CF
end
MOCK.isCF = isCF

CF.__index = function(c, k)
	if k == "Position" or k == "p" then
		return newV3(c.x, c.y, c.z)
	elseif k == "X" then
		return c.x
	elseif k == "Y" then
		return c.y
	elseif k == "Z" then
		return c.z
	elseif k == "LookVector" then
		return newV3(-c.r02, -c.r12, -c.r22)
	elseif k == "RightVector" then
		return newV3(c.r00, c.r10, c.r20)
	elseif k == "UpVector" then
		return newV3(c.r01, c.r11, c.r21)
	elseif k == "Rotation" then
		return newCFRaw(0, 0, 0, c.r00, c.r01, c.r02, c.r10, c.r11, c.r12, c.r20, c.r21, c.r22)
	end
	local m = rawget(CF, k)
	if m == nil then
		error("CFrame has no member " .. tostring(k), 2)
	end
	return m
end

local function mulCF(a, b)
	return newCFRaw(
		a.r00 * b.x + a.r01 * b.y + a.r02 * b.z + a.x,
		a.r10 * b.x + a.r11 * b.y + a.r12 * b.z + a.y,
		a.r20 * b.x + a.r21 * b.y + a.r22 * b.z + a.z,
		a.r00 * b.r00 + a.r01 * b.r10 + a.r02 * b.r20,
		a.r00 * b.r01 + a.r01 * b.r11 + a.r02 * b.r21,
		a.r00 * b.r02 + a.r01 * b.r12 + a.r02 * b.r22,
		a.r10 * b.r00 + a.r11 * b.r10 + a.r12 * b.r20,
		a.r10 * b.r01 + a.r11 * b.r11 + a.r12 * b.r21,
		a.r10 * b.r02 + a.r11 * b.r12 + a.r12 * b.r22,
		a.r20 * b.r00 + a.r21 * b.r10 + a.r22 * b.r20,
		a.r20 * b.r01 + a.r21 * b.r11 + a.r22 * b.r21,
		a.r20 * b.r02 + a.r21 * b.r12 + a.r22 * b.r22
	)
end
CF.__mul = function(a, b)
	assert(isCF(a), "CFrame * : left side must be CFrame")
	if isCF(b) then
		return mulCF(a, b)
	elseif isV3(b) then
		return newV3(
			a.r00 * b.X + a.r01 * b.Y + a.r02 * b.Z + a.x,
			a.r10 * b.X + a.r11 * b.Y + a.r12 * b.Z + a.y,
			a.r20 * b.X + a.r21 * b.Y + a.r22 * b.Z + a.z
		)
	end
	error("CFrame * unsupported operand", 2)
end
CF.__add = function(a, b)
	assert(isCF(a) and isV3(b), "CFrame + expects Vector3")
	return newCFRaw(a.x + b.X, a.y + b.Y, a.z + b.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end
CF.__sub = function(a, b)
	assert(isCF(a) and isV3(b), "CFrame - expects Vector3")
	return newCFRaw(a.x - b.X, a.y - b.Y, a.z - b.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end
function CF.Inverse(c)
	-- rotation transpose
	local r00, r01, r02 = c.r00, c.r10, c.r20
	local r10, r11, r12 = c.r01, c.r11, c.r21
	local r20, r21, r22 = c.r02, c.r12, c.r22
	local x = -(r00 * c.x + r01 * c.y + r02 * c.z)
	local y = -(r10 * c.x + r11 * c.y + r12 * c.z)
	local z = -(r20 * c.x + r21 * c.y + r22 * c.z)
	return newCFRaw(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end
function CF.ToWorldSpace(a, b)
	return a * b
end
function CF.ToObjectSpace(a, b)
	return a:Inverse() * b
end
function CF.PointToWorldSpace(a, v)
	return a * v
end
function CF.PointToObjectSpace(a, v)
	return a:Inverse() * v
end
function CF.VectorToWorldSpace(a, v)
	return a.Rotation * v
end
function CF.VectorToObjectSpace(a, v)
	return a.Rotation:Inverse() * v
end
function CF.GetComponents(c)
	return c.x, c.y, c.z, c.r00, c.r01, c.r02, c.r10, c.r11, c.r12, c.r20, c.r21, c.r22
end
function CF.Lerp(a, b, t)
	-- good enough for a mock: lerp position, keep a's rotation
	local p = a.Position:Lerp(b.Position, t)
	return newCFRaw(p.X, p.Y, p.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end

local function rotX(a)
	local c, s = math.cos(a), math.sin(a)
	return newCFRaw(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
end
local function rotY(a)
	local c, s = math.cos(a), math.sin(a)
	return newCFRaw(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
end
local function rotZ(a)
	local c, s = math.cos(a), math.sin(a)
	return newCFRaw(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
end

local function fromMatrix(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy)
	return newCFRaw(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end

local function lookAt(at, target, up)
	up = up or newV3(0, 1, 0)
	local f = (target - at)
	if f.Magnitude < 1e-9 then
		return newCFRaw(at.X, at.Y, at.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	f = f.Unit
	local r = f:Cross(up)
	if r.Magnitude < 1e-6 then
		r = f:Cross(newV3(0, 0, 1))
		if r.Magnitude < 1e-6 then
			r = f:Cross(newV3(1, 0, 0))
		end
	end
	r = r.Unit
	local u = r:Cross(f).Unit
	return fromMatrix(at, r, u, -f)
end

CFrame = {
	new = function(a, b, c, ...)
		if a == nil then
			return newCFRaw(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		end
		if isV3(a) then
			if b ~= nil then
				assert(isV3(b), "CFrame.new(Vector3, Vector3)")
				return lookAt(a, b)
			end
			return newCFRaw(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		end
		assert(type(a) == "number" and type(b) == "number" and type(c) == "number", "CFrame.new expects numbers")
		local rest = { ... }
		if #rest == 9 then
			return newCFRaw(a, b, c, table.unpack(rest))
		end
		return newCFRaw(a, b, c, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end,
	Angles = function(rx, ry, rz)
		assert(type(rx) == "number" and type(ry) == "number" and type(rz) == "number", "CFrame.Angles expects 3 numbers")
		return rotX(rx) * rotY(ry) * rotZ(rz)
	end,
	fromEulerAnglesXYZ = function(rx, ry, rz)
		return rotX(rx) * rotY(ry) * rotZ(rz)
	end,
	fromEulerAnglesYXZ = function(rx, ry, rz)
		return rotY(ry) * rotX(rx) * rotZ(rz)
	end,
	fromOrientation = function(rx, ry, rz)
		return rotY(ry) * rotX(rx) * rotZ(rz)
	end,
	fromAxisAngle = function(axis, a)
		local u = axis.Unit
		local c, s = math.cos(a), math.sin(a)
		local t = 1 - c
		local x, y, z = u.X, u.Y, u.Z
		return newCFRaw(
			0,
			0,
			0,
			t * x * x + c,
			t * x * y - s * z,
			t * x * z + s * y,
			t * x * y + s * z,
			t * y * y + c,
			t * y * z - s * x,
			t * x * z - s * y,
			t * y * z + s * x,
			t * z * z + c
		)
	end,
	lookAt = lookAt,
	fromMatrix = fromMatrix,
	identity = newCFRaw(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
}

---------------------------------------------------------------- Color3 & friends
local C3 = {}
C3.__index = C3
local function newC3(r, g, b)
	assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "Color3 expects numbers")
	return setmetatable({ R = r, G = g, B = b }, C3)
end
function C3.Lerp(a, b, t)
	return newC3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3.ToHSV(c)
	return 0, 0, math.max(c.R, c.G, c.B)
end
Color3 = {
	new = newC3,
	fromRGB = function(r, g, b)
		for _, v in ipairs({ r, g, b }) do
			if v < -0.01 or v > 255.01 then
				mockWarn("Color3.fromRGB component out of range: " .. tostring(v))
			end
		end
		return newC3(r / 255, g / 255, b / 255)
	end,
	fromHSV = function(h, s, v)
		return newC3(v, v, v)
	end,
}
MOCK.isC3 = function(c)
	return getmetatable(c) == C3
end

BrickColor = {
	new = function(n)
		return { Name = n }
	end,
}

NumberRange = {
	new = function(a, b)
		return { Min = a, Max = b or a }
	end,
}
NumberSequenceKeypoint = {
	new = function(t, v, e)
		assert(t >= 0 and t <= 1, "keypoint time out of range")
		return { Time = t, Value = v, Envelope = e or 0 }
	end,
}
NumberSequence = {
	new = function(a, b)
		if type(a) == "table" then
			assert(a[1].Time == 0 and a[#a].Time == 1, "NumberSequence must start at 0 and end at 1")
			return { Keypoints = a }
		end
		return { Keypoints = { a, b or a } }
	end,
}
ColorSequenceKeypoint = {
	new = function(t, c)
		assert(t >= 0 and t <= 1, "keypoint time out of range")
		return { Time = t, Value = c }
	end,
}
ColorSequence = {
	new = function(a, b)
		if type(a) == "table" and a.R == nil then
			assert(a[1].Time == 0 and a[#a].Time == 1, "ColorSequence must start at 0 and end at 1")
			return { Keypoints = a }
		end
		return { Keypoints = { a, b or a } }
	end,
}
UDim2 = {
	new = function(...)
		return { ... }
	end,
	fromScale = function(...)
		return { ... }
	end,
	fromOffset = function(...)
		return { ... }
	end,
}
UDim = {
	new = function(...)
		return { ... }
	end,
}
TweenInfo = {
	new = function(...)
		return { ... }
	end,
}
PhysicalProperties = {
	new = function(...)
		return { ... }
	end,
}
Font = {
	new = function(...)
		return { ... }
	end,
	fromEnum = function(...)
		return { ... }
	end,
}

Region3 = {
	new = function(a, b)
		local r = { Min = a, Max = b, Size = b - a, CFrame = CFrame.new((a + b) / 2) }
		function r:ExpandToGrid(res)
			assert(res == 4, "ExpandToGrid resolution must be 4")
			local function snapDown(v)
				return math.floor(v / 4) * 4
			end
			local function snapUp(v)
				return math.ceil(v / 4) * 4
			end
			return Region3.new(
				newV3(snapDown(a.X), snapDown(a.Y), snapDown(a.Z)),
				newV3(snapUp(b.X), snapUp(b.Y), snapUp(b.Z))
			)
		end
		return r
	end,
}

---------------------------------------------------------------- Random
local RNG = {}
RNG.__index = RNG
function RNG:_next()
	-- xorshift-ish LCG, deterministic
	self.s = (self.s * 1103515245 + 12345) % 2147483648
	return self.s / 2147483648
end
function RNG:NextNumber(a, b)
	if a == nil then
		return self:_next()
	end
	return a + (b - a) * self:_next()
end
function RNG:NextInteger(a, b)
	assert(a <= b, "NextInteger: min > max")
	return a + math.floor(self:_next() * (b - a + 1))
end
function RNG:NextUnitVector()
	local v
	repeat
		v = newV3(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1))
	until v.Magnitude > 0.1 and v.Magnitude <= 1
	return v.Unit
end
function RNG:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end
Random = {
	new = function(seed)
		return setmetatable({ s = math.floor(math.abs(seed or 1)) % 2147483648 + 1 }, RNG)
	end,
}

---------------------------------------------------------------- Enum
local enumTypes = {}
local function enumItem(typeName, name)
	return setmetatable({ Name = name, EnumType = typeName }, {
		__tostring = function()
			return "Enum." .. typeName .. "." .. name
		end,
	})
end
local KNOWN_ENUMS = {
	Material = {
		"Plastic",
		"SmoothPlastic",
		"Neon",
		"Wood",
		"WoodPlanks",
		"Marble",
		"Slate",
		"Concrete",
		"Granite",
		"Brick",
		"Pebble",
		"Cobblestone",
		"CorrodedMetal",
		"DiamondPlate",
		"Foil",
		"Metal",
		"Grass",
		"LeafyGrass",
		"Sand",
		"Fabric",
		"Ice",
		"Glass",
		"ForceField",
		"Basalt",
		"Ground",
		"CrackedLava",
		"Asphalt",
		"Limestone",
		"Mud",
		"Pavement",
		"Plaster",
		"Rock",
		"Salt",
		"Sandstone",
		"Snow",
		"Glacier",
		"Water",
		"Air",
		"Cardboard",
		"Carpet",
		"CeramicTiles",
		"ClayRoofTiles",
		"RoofShingles",
		"Leather",
		"Rubber",
	},
	PartType = { "Ball", "Block", "Cylinder", "Wedge", "CornerWedge" },
	SurfaceType = { "Smooth", "SmoothNoOutlines", "Studs", "Inlet", "Universal" },
	NormalId = { "Top", "Bottom", "Front", "Back", "Left", "Right" },
	MeshType = { "Brick", "Cylinder", "Head", "Sphere", "Torso", "Wedge", "FileMesh" },
	ModelStreamingMode = { "Default", "Atomic", "Persistent", "PersistentPerPlayer", "Nonatomic" },
	Technology = { "Legacy", "Voxel", "Compatibility", "ShadowMap", "Future", "Unified" },
	EasingStyle = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back", "Bounce", "Elastic" },
	EasingDirection = { "In", "Out", "InOut" },
	ParticleEmitterShape = { "Box", "Sphere", "Cylinder", "Disc" },
	ParticleEmitterShapeStyle = { "Volume", "Surface" },
	ParticleEmitterShapeInOut = { "Outward", "Inward", "InAndOut" },
	ParticleOrientation = { "FacingCamera", "FacingCameraWorldUp", "VelocityParallel", "VelocityPerpendicular" },
	Font = { "Garamond", "Antique", "SourceSans", "GothamBold", "Gotham", "Fantasy", "Bodoni" },
	StreamingIntegrityMode = { "Default", "Disabled", "MinimumRadiusPause", "PauseOutsideLoadedArea" },
	StreamOutBehavior = { "Default", "LowMemory", "Opportunistic" },
	LevelOfDetailSetting = { "Automatic", "StreamingMesh", "Disabled" },
	ModelLevelOfDetail = { "Automatic", "StreamingMesh", "Disabled" },
	KeyCode = { "Unknown" },
	RenderPriority = { "Camera" },
}
Enum = setmetatable({}, {
	__index = function(_, typeName)
		local t = enumTypes[typeName]
		if t then
			return t
		end
		local known = KNOWN_ENUMS[typeName]
		if not known then
			error("Unknown enum type Enum." .. tostring(typeName), 2)
		end
		local items = {}
		for _, n in ipairs(known) do
			items[n] = enumItem(typeName, n)
		end
		t = setmetatable({}, {
			__index = function(_, name)
				local it = items[name]
				if not it then
					error("Unknown enum item Enum." .. typeName .. "." .. tostring(name), 2)
				end
				return it
			end,
		})
		enumTypes[typeName] = t
		return t
	end,
})

---------------------------------------------------------------- Instances
local PART_PROPS = {
	"Anchored",
	"CanCollide",
	"CanTouch",
	"CanQuery",
	"CastShadow",
	"Size",
	"CFrame",
	"Position",
	"Orientation",
	"Color",
	"BrickColor",
	"Material",
	"Transparency",
	"Reflectance",
	"Shape",
	"TopSurface",
	"BottomSurface",
	"LeftSurface",
	"RightSurface",
	"FrontSurface",
	"BackSurface",
	"Locked",
	"Massless",
	"MaterialVariant",
	"LocalTransparencyModifier",
	"AssemblyLinearVelocity",
}
local LIGHT_PROPS = { "Brightness", "Range", "Color", "Shadows", "Enabled", "Angle", "Face" }

local CLASS = {
	Part = { base = "BasePart", props = PART_PROPS },
	WedgePart = { base = "BasePart", props = PART_PROPS },
	CornerWedgePart = { base = "BasePart", props = PART_PROPS },
	TrussPart = { base = "BasePart", props = PART_PROPS },
	SpawnLocation = {
		base = "BasePart",
		props = PART_PROPS,
		extra = { "Neutral", "Duration", "Enabled", "AllowTeamChangeOnTouch", "TeamColor" },
	},
	Model = { props = { "WorldPivot", "PrimaryPart", "ModelStreamingMode", "LevelOfDetail" } },
	Folder = { props = {} },
	PointLight = { base = "Light", props = LIGHT_PROPS },
	SpotLight = { base = "Light", props = LIGHT_PROPS },
	SurfaceLight = { base = "Light", props = LIGHT_PROPS },
	Attachment = { props = { "Position", "CFrame", "Orientation", "Axis", "SecondaryAxis", "Visible" } },
	ParticleEmitter = {
		props = {
			"Texture",
			"Color",
			"Size",
			"Transparency",
			"Lifetime",
			"Rate",
			"Speed",
			"SpreadAngle",
			"Acceleration",
			"Drag",
			"LightEmission",
			"LightInfluence",
			"Rotation",
			"RotSpeed",
			"EmissionDirection",
			"Shape",
			"ShapeStyle",
			"ShapeInOut",
			"ShapePartial",
			"Enabled",
			"LockedToPart",
			"ZOffset",
			"Orientation",
			"VelocityInheritance",
			"Brightness",
			"TimeScale",
			"Squash",
			"WindAffectsDrag",
		},
	},
	Fire = { props = { "Size", "Heat", "Color", "SecondaryColor", "Enabled", "TimeScale" } },
	Smoke = { props = { "Color", "Opacity", "RiseVelocity", "Size", "Enabled", "TimeScale" } },
	Sparkles = { props = { "SparkleColor", "Enabled", "TimeScale" } },
	Beam = {
		props = {
			"Attachment0",
			"Attachment1",
			"Color",
			"Transparency",
			"Width0",
			"Width1",
			"LightEmission",
			"LightInfluence",
			"FaceCamera",
			"Segments",
			"Texture",
			"TextureSpeed",
			"TextureLength",
			"CurveSize0",
			"CurveSize1",
			"Brightness",
			"Enabled",
		},
	},
	SpecialMesh = { props = { "MeshType", "Scale", "Offset", "MeshId", "TextureId", "VertexColor" } },
	Atmosphere = { props = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" } },
	Sky = {
		props = {
			"SkyboxBk",
			"SkyboxDn",
			"SkyboxFt",
			"SkyboxLf",
			"SkyboxRt",
			"SkyboxUp",
			"CelestialBodiesShown",
			"MoonAngularSize",
			"MoonTextureId",
			"StarCount",
			"SunAngularSize",
			"SunTextureId",
		},
	},
	BloomEffect = { props = { "Intensity", "Size", "Threshold", "Enabled" } },
	ColorCorrectionEffect = { props = { "Brightness", "Contrast", "Saturation", "TintColor", "Enabled" } },
	SunRaysEffect = { props = { "Intensity", "Spread", "Enabled" } },
	DepthOfFieldEffect = { props = { "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity", "Enabled" } },
	Clouds = { props = { "Cover", "Density", "Color", "Enabled" } },
	ModuleScript = { props = { "Source" } },
	LocalScript = { props = { "Source", "Disabled", "Enabled", "RunContext" } },
	Script = { props = { "Source", "Disabled", "Enabled", "RunContext" } },
	StringValue = { props = { "Value" } },
	NumberValue = { props = { "Value" } },
	ObjectValue = { props = { "Value" } },
	Sound = { props = { "SoundId", "Volume", "Looped", "Playing", "PlaybackSpeed", "RollOffMaxDistance" } },
	SurfaceGui = { props = { "Face", "CanvasSize", "LightInfluence", "SizingMode", "PixelsPerStud", "AlwaysOnTop", "Adornee" } },
	TextLabel = {
		props = {
			"Size",
			"Position",
			"AnchorPoint",
			"BackgroundTransparency",
			"BackgroundColor3",
			"Text",
			"TextColor3",
			"TextStrokeColor3",
			"TextStrokeTransparency",
			"TextTransparency",
			"Font",
			"FontFace",
			"TextScaled",
			"TextSize",
			"TextWrapped",
		},
	},
}

local Inst = {}
local instMeta = {}

local function className(o)
	return rawget(o, "__class")
end

local function isA(cls, query)
	if cls == query or query == "Instance" then
		return true
	end
	local def = CLASS[cls]
	if def and def.base == query then
		return true
	end
	if query == "LuaSourceContainer" and (cls == "ModuleScript" or cls == "LocalScript" or cls == "Script") then
		return true
	end
	if query == "PVInstance" and (cls == "Model" or (def and def.base == "BasePart")) then
		return true
	end
	return false
end

local function allowed(o, k)
	if k == "Name" or k == "Parent" or k == "Archivable" then
		return true
	end
	local cls = className(o)
	if rawget(o, "__service") then
		return true
	end
	local def = CLASS[cls]
	if not def then
		error("Mock: unsupported class " .. tostring(cls))
	end
	for _, p in ipairs(def.props) do
		if p == k then
			return true
		end
	end
	if def.extra then
		for _, p in ipairs(def.extra) do
			if p == k then
				return true
			end
		end
	end
	return false
end

local function children(o)
	return rawget(o, "__children")
end

local function setParent(o, p)
	local old = rawget(o, "__props").Parent
	if old == p then
		return
	end
	if old then
		local list = children(old)
		for i, c in ipairs(list) do
			if c == o then
				table.remove(list, i)
				break
			end
		end
	end
	rawget(o, "__props").Parent = p
	if p then
		table.insert(children(p), o)
	end
end

local function checkPart(o, k, v)
	if k == "Size" then
		assert(MOCK.isV3(v), "Part.Size must be a Vector3")
		if v.X > 2048 or v.Y > 2048 or v.Z > 2048 then
			mockWarn("part larger than 2048 studs on an axis (" .. tostring(rawget(o, "__props").Name) .. ")")
		end
		if v.X <= 0 or v.Y <= 0 or v.Z <= 0 then
			error("Part.Size must be positive, got " .. tostring(v), 3)
		end
		if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then
			error("Part.Size is NaN", 3)
		end
	elseif k == "CFrame" then
		assert(MOCK.isCF(v), "Part.CFrame must be a CFrame")
	elseif k == "Position" then
		assert(MOCK.isV3(v), "Part.Position must be a Vector3")
	elseif k == "Color" then
		assert(MOCK.isC3(v), "Part.Color must be a Color3")
	elseif k == "Material" then
		assert(type(v) == "table" and v.EnumType == "Material", "Part.Material must be Enum.Material")
	elseif k == "Transparency" or k == "Reflectance" then
		assert(type(v) == "number", k .. " must be a number")
	end
end

instMeta.__index = function(o, k)
	local props = rawget(o, "__props")
	local v = props[k]
	if v ~= nil then
		return v
	end
	local m = Inst[k]
	if m then
		return m
	end
	-- child lookup like Roblox (o.ChildName)
	for _, c in ipairs(children(o)) do
		if rawget(c, "__props").Name == k then
			return c
		end
	end
	if k == "Parent" then
		return nil
	end
	if allowed(o, k) then
		return nil
	end
	error(tostring(props.Name) .. " (" .. tostring(className(o)) .. ") has no member " .. tostring(k), 2)
end

instMeta.__newindex = function(o, k, v)
	if not allowed(o, k) then
		error("Mock: " .. tostring(className(o)) .. " has no property '" .. tostring(k) .. "'", 2)
	end
	if k == "Parent" then
		setParent(o, v)
		return
	end
	local cls = className(o)
	local def = CLASS[cls]
	if def and def.base == "BasePart" then
		checkPart(o, k, v)
		local props = rawget(o, "__props")
		if k == "Position" then
			local cf = props.CFrame
			props.CFrame = CFrame.new(v) * cf.Rotation
			props.Position = v
			return
		elseif k == "CFrame" then
			props.Position = v.Position
		elseif k == "Shape" then
			props.Shape = v
			return
		end
	end
	if cls == "Light" or (def and def.base == "Light") then
		if k == "Range" and v > 60 then
			mockWarn("light Range above 60 is clamped by Roblox")
		end
	end
	rawget(o, "__props")[k] = v
end

instMeta.__tostring = function(o)
	return rawget(o, "__props").Name
end

local function newInstance(cls, parent)
	MOCK.instanceCount += 1
	local o = setmetatable({ __class = cls, __props = { Name = cls }, __children = {}, __attrs = {} }, instMeta)
	local def = CLASS[cls]
	if not def then
		error("Mock: Instance.new of unsupported class " .. tostring(cls), 2)
	end
	if def.base == "BasePart" then
		MOCK.partCount += 1
		local p = rawget(o, "__props")
		p.Size = Vector3.new(4, 1, 2)
		p.CFrame = CFrame.new()
		p.Position = Vector3.new()
		p.Anchored = false
		p.Transparency = 0
		p.Material = Enum.Material.Plastic
	end
	if cls == "Model" then
		rawget(o, "__props").WorldPivot = CFrame.new()
	end
	if parent then
		o.Parent = parent
	end
	return o
end

Instance = { new = newInstance }

function Inst.IsA(o, q)
	return isA(className(o), q)
end
function Inst.GetChildren(o)
	return table.clone(children(o))
end
function Inst.GetDescendants(o)
	local out = {}
	local function walk(x)
		for _, c in ipairs(children(x)) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(o)
	return out
end
function Inst.FindFirstChild(o, name, recursive)
	for _, c in ipairs(children(o)) do
		if rawget(c, "__props").Name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(children(o)) do
			local f = Inst.FindFirstChild(c, name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function Inst.WaitForChild(o, name)
	local c = Inst.FindFirstChild(o, name)
	if not c then
		error("WaitForChild would hang: " .. name)
	end
	return c
end
function Inst.FindFirstChildOfClass(o, cls)
	for _, c in ipairs(children(o)) do
		if className(c) == cls then
			return c
		end
	end
	return nil
end
function Inst.FindFirstChildWhichIsA(o, cls)
	for _, c in ipairs(children(o)) do
		if isA(className(c), cls) then
			return c
		end
	end
	return nil
end
function Inst.Destroy(o)
	for _, c in ipairs(table.clone(children(o))) do
		Inst.Destroy(c)
	end
	if className(o) and CLASS[className(o)] and CLASS[className(o)].base == "BasePart" then
		MOCK.partCount -= 1
	end
	setParent(o, nil)
end
function Inst.ClearAllChildren(o)
	for _, c in ipairs(table.clone(children(o))) do
		Inst.Destroy(c)
	end
end
function Inst.Clone(o)
	local cls = className(o)
	local c = newInstance(cls)
	local props = rawget(c, "__props")
	for k, v in pairs(rawget(o, "__props")) do
		if k ~= "Parent" then
			props[k] = v
		end
	end
	for _, ch in ipairs(children(o)) do
		local cc = Inst.Clone(ch)
		cc.Parent = c
	end
	return c
end
function Inst.SetAttribute(o, k, v)
	rawget(o, "__attrs")[k] = v
end
function Inst.GetAttribute(o, k)
	return rawget(o, "__attrs")[k]
end

local function eachPart(o, fn)
	for _, d in ipairs(Inst.GetDescendants(o)) do
		local def = CLASS[className(d)]
		if def and def.base == "BasePart" then
			fn(d)
		end
	end
end

function Inst.GetPivot(o)
	local cls = className(o)
	if cls == "Model" then
		local pp = rawget(o, "__props").PrimaryPart
		if pp then
			return pp.CFrame
		end
		return rawget(o, "__props").WorldPivot
	end
	return o.CFrame
end
function Inst.PivotTo(o, cf)
	assert(MOCK.isCF(cf), "PivotTo expects a CFrame")
	local cls = className(o)
	if cls == "Model" then
		local old = Inst.GetPivot(o)
		local delta = cf * old:Inverse()
		eachPart(o, function(p)
			p.CFrame = delta * p.CFrame
		end)
		rawget(o, "__props").WorldPivot = cf
	else
		o.CFrame = cf
	end
end
function Inst.ScaleTo(o, s)
	assert(className(o) == "Model", "ScaleTo is a Model method")
	assert(type(s) == "number" and s > 0, "ScaleTo expects a positive number")
	local cur = rawget(o, "__attrs").__scale or 1
	local f = s / cur
	local pivot = Inst.GetPivot(o)
	eachPart(o, function(p)
		local rel = pivot:Inverse() * p.CFrame
		local pos = rel.Position * f
		p.CFrame = pivot * (CFrame.new(pos) * rel.Rotation)
		p.Size = p.Size * f
	end)
	rawget(o, "__attrs").__scale = s
end
function Inst.GetScale(o)
	return rawget(o, "__attrs").__scale or 1
end

---------------------------------------------------------------- Services
local function service(name, cls)
	local o = setmetatable({ __class = cls or name, __props = { Name = name }, __children = {}, __attrs = {}, __service = true }, instMeta)
	return o
end

local gameObj = service("Game", "DataModel")
local workspaceObj = service("Workspace")
workspaceObj.Parent = gameObj
local terrain = service("Terrain")
terrain.Parent = workspaceObj

MOCK.materialColors = {}
local function checkMat(m)
	assert(type(m) == "table" and m.EnumType == "Material", "terrain material must be Enum.Material")
end
local TerrainMethods = {}
function TerrainMethods.Clear() end
function TerrainMethods.FillBlock(_, cf, size, mat)
	assert(MOCK.isCF(cf) and MOCK.isV3(size), "FillBlock(CFrame, Vector3, Material)")
	checkMat(mat)
	MOCK.fillCalls += 1
end
MOCK.fills = {}
function TerrainMethods.FillBall(_, pos, radius, mat)
	assert(MOCK.isV3(pos) and type(radius) == "number", "FillBall(Vector3, number, Material)")
	checkMat(mat)
	MOCK.fillCalls += 1
	table.insert(MOCK.fills, { "ball", CFrame.new(pos), radius, mat.Name })
end
function TerrainMethods.FillCylinder(_, cf, height, radius, mat)
	assert(MOCK.isCF(cf) and type(height) == "number" and type(radius) == "number", "FillCylinder(CFrame, h, r, Material)")
	checkMat(mat)
	MOCK.fillCalls += 1
	table.insert(MOCK.fills, { "cyl", cf, radius, mat.Name, height })
end
function TerrainMethods.FillWedge(_, cf, size, mat)
	assert(MOCK.isCF(cf) and MOCK.isV3(size), "FillWedge(CFrame, Vector3, Material)")
	checkMat(mat)
	MOCK.fillCalls += 1
end
function TerrainMethods.SetMaterialColor(_, mat, color)
	checkMat(mat)
	assert(MOCK.isC3(color), "SetMaterialColor expects Color3")
	MOCK.materialColors[mat.Name] = color
end
MOCK.onWriteVoxels = nil
function TerrainMethods.WriteVoxels(_, region, res, mats, occs)
	assert(res == 4, "WriteVoxels resolution must be 4")
	local sx = (region.Max.X - region.Min.X) / 4
	local sy = (region.Max.Y - region.Min.Y) / 4
	local sz = (region.Max.Z - region.Min.Z) / 4
	assert(#mats == sx and #occs == sx, "WriteVoxels: X size mismatch " .. #mats .. " vs " .. sx)
	assert(#mats[1] == sy and #occs[1] == sy, "WriteVoxels: Y size mismatch " .. #mats[1] .. " vs " .. sy)
	assert(#mats[1][1] == sz and #occs[1][1] == sz, "WriteVoxels: Z size mismatch")
	for i = 1, sx, 7 do
		for j = 1, sy, 5 do
			for k = 1, sz, 7 do
				local m = mats[i][j][k]
				checkMat(m)
				local o = occs[i][j][k]
				assert(type(o) == "number" and o >= 0 and o <= 1, "bad occupancy")
			end
		end
	end
	MOCK.voxelWrites += sx * sy * sz
	if MOCK.onWriteVoxels then
		MOCK.onWriteVoxels(region, mats, occs)
	end
end
for k, f in pairs(TerrainMethods) do
	rawget(terrain, "__props")[k] = f
end

local lighting = service("Lighting")
lighting.Parent = gameObj
local services = {
	Workspace = workspaceObj,
	Lighting = lighting,
	ReplicatedStorage = service("ReplicatedStorage"),
	ServerStorage = service("ServerStorage"),
	ServerScriptService = service("ServerScriptService"),
	StarterPlayer = service("StarterPlayer"),
	SoundService = service("SoundService"),
	ChangeHistoryService = service("ChangeHistoryService"),
	RunService = service("RunService"),
	Players = service("Players"),
	TweenService = service("TweenService"),
}
for _, s in pairs(services) do
	if s ~= workspaceObj and s ~= lighting then
		s.Parent = gameObj
	end
end
local sps = service("StarterPlayerScripts")
sps.Parent = services.StarterPlayer
rawget(services.ChangeHistoryService, "__props").SetWaypoint = function() end
rawget(services.RunService, "__props").IsStudio = function()
	return true
end
rawget(services.RunService, "__props").IsRunning = function()
	return false
end

rawget(gameObj, "__props").GetService = function(_, name)
	local s = services[name]
	if not s then
		error("Mock: unknown service " .. name)
	end
	return s
end
rawget(workspaceObj, "__props").Terrain = terrain



game = gameObj
workspace = workspaceObj

---------------------------------------------------------------- task
MOCK.clock = 0
task = {
	wait = function(t)
		MOCK.waits = (MOCK.waits or 0) + 1
		return t or 0
	end,
	spawn = function(f, ...)
		f(...)
	end,
	defer = function(f, ...)
		f(...)
	end,
	delay = function() end,
}
wait = task.wait

local realWarn = warn or print
function warn(...)
	realWarn("[warn]", ...)
end

return MOCK
