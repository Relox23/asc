--!nocheck
-- Roblox API mock used to run the generator and the intro cutscene outside Studio.
-- It is strict on purpose: unknown property names, wrong value types, writes to
-- read-only properties and unknown enum items all error here instead of in Studio.
-- Only APIs that exist in real Roblox are mocked.
--
-- Client-side simulation (see MOCK.step): a fake clock, the RunService frame
-- phases, a task scheduler, tweens, a simple Animator, Motor6D/Weld solving and a
-- default "PlayerModule" camera, so a LocalScript can be played frame by frame.
--
-- Driver API (all on the MOCK table the bundle exposes):
--   setupClient{name, userId, rig = "R15"|"R6", spawn = CFrame} -> Players.LocalPlayer with
--       PlayerScripts.PlayerModule (GetControls():Enable/Disable -> MOCK.controlsEnabled),
--       PlayerGui, Backpack and a character; the main thread becomes client code
--   makeCharacter(rig, name) -> unparented character Model (R15 joints/sizes = DESIGN §4.1)
--   spawnCharacter(cf, rig)    respawn the local player's character
--   step(dt) -> CPU seconds    one frame (phase order documented at the function)
--   run(seconds, dt)           several frames
--   solveJoints(model?)        Part1 = Part0 * C0 * Transform * C1:Inverse() down each assembly
--   useFakeClock()             os.clock() returns MOCK.clock (MOCK.realClock stays real)
--   pressKey/releaseKey/tapKey(Enum.KeyCode.X)  ContextActionService + UserInputService input
--   runInContext("client"|"server"|"edit", fn, ...)  run code as a client or server script
--   startScript(script, body, force)  how the bundle's runScript starts Scripts/LocalScripts
--   groundY / raycastHook      what workspace:Raycast hits besides parts
--   errors, warnings, warnLog  thread errors, MOCKWARN messages, warn() output
--   remoteLog, soundLog, streamRequests, coreGui, core, renderBindings(), boundActions(),
--   connectionCount(signal), propertyNames(inst), classCounts, instanceCount  for checks
-- Threads started by the scheduler report errors to MOCK.errors (printed as MOCKERROR)
-- instead of throwing, like Roblox. task.wait on the main thread returns immediately (the
-- generator runs as one long call); inside a coroutine it yields until MOCK.step passes the time.

local MOCK = {
	warnings = {}, -- [message] = count; drivers print these as MOCKWARN
	partCount = 0,
	voxelWrites = 0,
	fillCalls = 0,
	instanceCount = 0,
	classCounts = {}, -- [className] = instances created
	errors = {}, -- errors thrown inside threads/handlers run by the scheduler
	warnLog = {}, -- messages passed to warn()
	clock = 0, -- simulated seconds (advanced by MOCK.step)
	frame = 0,
	groundY = 30, -- workspace:Raycast hits a flat ground at this height (nil = no ground)
	raycastHook = nil, -- function(origin, dir, params) -> RaycastResult | false | nil (nil = default)
	studio = true, -- RunService:IsStudio()
	running = false, -- RunService:IsRunning(); MOCK.setupClient sets it
	viewportSize = nil, -- Vector2, set below
	guiInset = 58, -- GuiService:GetGuiInset() top inset
	controlsEnabled = true, -- PlayerModule controls (GetControls():Enable/Disable)
	remoteLog = {}, -- { {remote=, dir="server"|"client", args=} }
	soundLog = {}, -- { {id=, t=} } every Sound:Play
	streamRequests = {}, -- Player:RequestStreamAroundAsync calls
	raycasts = 0,
	particlesEmitted = 0,
	cameraZoom = 12.5, -- distance used by the mock default camera
}
local realClock = os.clock
MOCK.realClock = realClock

local function mockWarn(msg)
	MOCK.warnings[msg] = (MOCK.warnings[msg] or 0) + 1
end
MOCK.warn = mockWarn

---------------------------------------------------------------- typeof
-- Roblox's typeof knows the engine types; the mock types are tables, so map their metatables.
local TYPE_NAMES = {}
local rawtypeof = typeof
typeof = function(v)
	if type(v) == "table" then
		local mt = getmetatable(v)
		if mt ~= nil then
			local n = TYPE_NAMES[mt]
			if n then
				return n
			end
		end
	end
	return rawtypeof(v)
end
MOCK.TYPE_NAMES = TYPE_NAMES

local function strictIndex(typeName, methods)
	return function(_, k)
		local m = methods[k]
		if m == nil then
			error(typeName .. " has no member " .. tostring(k), 2)
		end
		return m
	end
end
local function immutable(typeName)
	return function(_, k)
		error(typeName .. "." .. tostring(k) .. " cannot be assigned to", 2)
	end
end

---------------------------------------------------------------- Vector3
local V3 = {}
local V3methods = {}
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
	local m = V3methods[k]
	if m == nil then
		error("Vector3 has no member " .. tostring(k), 2)
	end
	return m
end
V3.__newindex = immutable("Vector3")
TYPE_NAMES[V3] = "Vector3"
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
		assert(isV3(b), "bad Vector3 multiply")
		return newV3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return newV3(a.X * b, a.Y * b, a.Z * b)
	end
	assert(isV3(a) and isV3(b), "bad Vector3 multiply")
	return newV3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(a) == "number" then
		return newV3(a / b.X, a / b.Y, a / b.Z)
	elseif type(b) == "number" then
		return newV3(a.X / b, a.Y / b, a.Z / b)
	end
	assert(isV3(a) and isV3(b), "bad Vector3 divide")
	return newV3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__idiv = function(a, b)
	if type(b) == "number" then
		return newV3(a.X // b, a.Y // b, a.Z // b)
	end
	return newV3(a.X // b.X, a.Y // b.Y, a.Z // b.Z)
end
V3.__unm = function(a)
	return newV3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return isV3(a) and isV3(b) and a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z)
end
function V3.Dot(a, b)
	assert(isV3(b), "Vector3:Dot expects a Vector3")
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3.Cross(a, b)
	assert(isV3(b), "Vector3:Cross expects a Vector3")
	return newV3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a, b, t)
	assert(isV3(b) and type(t) == "number", "Vector3:Lerp(Vector3, number)")
	return a + (b - a) * t
end
function V3.Abs(a)
	return newV3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3.Floor(a)
	return newV3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
end
function V3.Ceil(a)
	return newV3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z))
end
function V3.Sign(a)
	return newV3(math.sign(a.X), math.sign(a.Y), math.sign(a.Z))
end
function V3.Max(a, b)
	return newV3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function V3.Min(a, b)
	return newV3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function V3.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps and math.abs(a.Z - b.Z) <= eps
end
function V3.Angle(a, b, axis)
	local d = a:Dot(b) / math.max(a.Magnitude * b.Magnitude, 1e-12)
	local ang = math.acos(math.clamp(d, -1, 1))
	if axis and a:Cross(b):Dot(axis) < 0 then
		ang = -ang
	end
	return ang
end
for k, v in pairs(V3) do
	if string.sub(k, 1, 2) ~= "__" then
		V3methods[k] = v
	end
end
Vector3 = {
	new = newV3,
	zero = newV3(0, 0, 0),
	one = newV3(1, 1, 1),
	xAxis = newV3(1, 0, 0),
	yAxis = newV3(0, 1, 0),
	zAxis = newV3(0, 0, 1),
	FromNormalId = function(n)
		local d = {
			Top = newV3(0, 1, 0),
			Bottom = newV3(0, -1, 0),
			Front = newV3(0, 0, -1),
			Back = newV3(0, 0, 1),
			Left = newV3(-1, 0, 0),
			Right = newV3(1, 0, 0),
		}
		return d[n.Name]
	end,
}
MOCK.isV3 = isV3

---------------------------------------------------------------- Vector2
local V2 = {}
local V2methods = {}
V2.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		if m == 0 then
			return Vector2.new(0 / 0, 0 / 0)
		end
		return Vector2.new(v.X / m, v.Y / m)
	elseif k == "x" or k == "y" then
		error("use uppercase Vector2 components", 2)
	end
	local m = V2methods[k]
	if m == nil then
		error("Vector2 has no member " .. tostring(k), 2)
	end
	return m
end
V2.__newindex = immutable("Vector2")
TYPE_NAMES[V2] = "Vector2"
local function isV2(v)
	return type(v) == "table" and getmetatable(v) == V2
end
local function newV2(x, y)
	x, y = x or 0, y or 0
	assert(type(x) == "number" and type(y) == "number", "Vector2.new expects numbers")
	return setmetatable({ X = x, Y = y }, V2)
end
V2.__add = function(a, b)
	assert(isV2(a) and isV2(b), "Vector2 + non-Vector2")
	return newV2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	assert(isV2(a) and isV2(b), "Vector2 - non-Vector2")
	return newV2(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return newV2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return newV2(a.X * b, a.Y * b)
	end
	assert(isV2(a) and isV2(b), "bad Vector2 multiply")
	return newV2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	if type(b) == "number" then
		return newV2(a.X / b, a.Y / b)
	end
	return newV2(a.X / b.X, a.Y / b.Y)
end
V2.__unm = function(a)
	return newV2(-a.X, -a.Y)
end
V2.__eq = function(a, b)
	return isV2(a) and isV2(b) and a.X == b.X and a.Y == b.Y
end
V2.__tostring = function(v)
	return string.format("%.2f, %.2f", v.X, v.Y)
end
function V2.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end
function V2.Cross(a, b)
	return a.X * b.Y - a.Y * b.X
end
function V2.Lerp(a, b, t)
	return a + (b - a) * t
end
function V2.Abs(a)
	return newV2(math.abs(a.X), math.abs(a.Y))
end
function V2.Max(a, b)
	return newV2(math.max(a.X, b.X), math.max(a.Y, b.Y))
end
function V2.Min(a, b)
	return newV2(math.min(a.X, b.X), math.min(a.Y, b.Y))
end
function V2.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps
end
for k, v in pairs(V2) do
	if string.sub(k, 1, 2) ~= "__" then
		V2methods[k] = v
	end
end
Vector2 = {
	new = newV2,
	zero = newV2(0, 0),
	one = newV2(1, 1),
	xAxis = newV2(1, 0),
	yAxis = newV2(0, 1),
}
MOCK.isV2 = isV2
MOCK.viewportSize = newV2(1280, 720)

---------------------------------------------------------------- CFrame
local CF = {}
local CFmethods = {}
TYPE_NAMES[CF] = "CFrame"
local function newCFRaw(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	if
		x ~= x or y ~= y or z ~= z or r00 ~= r00 or r01 ~= r01 or r02 ~= r02
		or r10 ~= r10 or r11 ~= r11 or r12 ~= r12 or r20 ~= r20 or r21 ~= r21 or r22 ~= r22
	then
		error("CFrame has NaN component", 3)
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
	elseif k == "LookVector" or k == "lookVector" then
		return newV3(-c.r02, -c.r12, -c.r22)
	elseif k == "RightVector" or k == "rightVector" or k == "XVector" then
		return newV3(c.r00, c.r10, c.r20)
	elseif k == "UpVector" or k == "upVector" or k == "YVector" then
		return newV3(c.r01, c.r11, c.r21)
	elseif k == "ZVector" then
		return newV3(c.r02, c.r12, c.r22)
	elseif k == "Rotation" then
		return newCFRaw(0, 0, 0, c.r00, c.r01, c.r02, c.r10, c.r11, c.r12, c.r20, c.r21, c.r22)
	end
	local m = CFmethods[k]
	if m == nil then
		error("CFrame has no member " .. tostring(k), 2)
	end
	return m
end
CF.__newindex = immutable("CFrame")

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
CF.__eq = function(a, b)
	if not (isCF(a) and isCF(b)) then
		return false
	end
	return a.x == b.x and a.y == b.y and a.z == b.z and a.r00 == b.r00 and a.r01 == b.r01 and a.r02 == b.r02
		and a.r10 == b.r10 and a.r11 == b.r11 and a.r12 == b.r12 and a.r20 == b.r20 and a.r21 == b.r21 and a.r22 == b.r22
end
CF.__tostring = function(c)
	return string.format(
		"%g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g",
		c.x, c.y, c.z, c.r00, c.r01, c.r02, c.r10, c.r11, c.r12, c.r20, c.r21, c.r22
	)
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
CF.components = CF.GetComponents

-- rotation matrix <-> quaternion (w, x, y, z)
local function quatFromCF(c)
	local tr = c.r00 + c.r11 + c.r22
	local w, x, y, z
	if tr > 0 then
		local s = math.sqrt(tr + 1) * 2
		w = 0.25 * s
		x = (c.r21 - c.r12) / s
		y = (c.r02 - c.r20) / s
		z = (c.r10 - c.r01) / s
	elseif c.r00 > c.r11 and c.r00 > c.r22 then
		local s = math.sqrt(1 + c.r00 - c.r11 - c.r22) * 2
		w = (c.r21 - c.r12) / s
		x = 0.25 * s
		y = (c.r01 + c.r10) / s
		z = (c.r02 + c.r20) / s
	elseif c.r11 > c.r22 then
		local s = math.sqrt(1 + c.r11 - c.r00 - c.r22) * 2
		w = (c.r02 - c.r20) / s
		x = (c.r01 + c.r10) / s
		y = 0.25 * s
		z = (c.r12 + c.r21) / s
	else
		local s = math.sqrt(1 + c.r22 - c.r00 - c.r11) * 2
		w = (c.r10 - c.r01) / s
		x = (c.r02 + c.r20) / s
		y = (c.r12 + c.r21) / s
		z = 0.25 * s
	end
	return w, x, y, z
end
local function cfFromQuat(px, py, pz, w, x, y, z)
	local m = math.sqrt(w * w + x * x + y * y + z * z)
	if m < 1e-12 then
		error("CFrame.new: zero quaternion", 3)
	end
	w, x, y, z = w / m, x / m, y / m, z / m
	return newCFRaw(
		px, py, pz,
		1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y),
		2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x),
		2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)
	)
end
MOCK.quatFromCF = quatFromCF
MOCK.cfFromQuat = cfFromQuat

function CF.Lerp(a, b, t)
	assert(isCF(b) and type(t) == "number", "CFrame:Lerp(CFrame, number)")
	local p = a.Position:Lerp(b.Position, t)
	local aw, ax, ay, az = quatFromCF(a)
	local bw, bx, by, bz = quatFromCF(b)
	local d = aw * bw + ax * bx + ay * by + az * bz
	if d < 0 then
		bw, bx, by, bz, d = -bw, -bx, -by, -bz, -d
	end
	local k0, k1
	if d > 0.9995 then
		k0, k1 = 1 - t, t
	else
		local th = math.acos(math.clamp(d, -1, 1))
		local s = math.sin(th)
		k0, k1 = math.sin((1 - t) * th) / s, math.sin(t * th) / s
	end
	return cfFromQuat(p.X, p.Y, p.Z, aw * k0 + bw * k1, ax * k0 + bx * k1, ay * k0 + by * k1, az * k0 + bz * k1)
end
function CF.ToEulerAnglesXYZ(c)
	local b = math.asin(math.clamp(c.r02, -1, 1))
	local a, g
	if math.abs(c.r02) < 0.9999999 then
		a = math.atan2(-c.r12, c.r22)
		g = math.atan2(-c.r01, c.r00)
	else
		a = math.atan2(c.r21, c.r11)
		g = 0
	end
	return a, b, g
end
CF.toEulerAnglesXYZ = CF.ToEulerAnglesXYZ
function CF.ToEulerAnglesYXZ(c)
	local a = math.asin(math.clamp(-c.r12, -1, 1))
	local b, g
	if math.abs(c.r12) < 0.9999999 then
		b = math.atan2(c.r02, c.r22)
		g = math.atan2(c.r10, c.r11)
	else
		b = math.atan2(-c.r20, c.r00)
		g = 0
	end
	return a, b, g
end
CF.toEulerAnglesYXZ = CF.ToEulerAnglesYXZ
CF.ToOrientation = CF.ToEulerAnglesYXZ
function CF.ToAxisAngle(c)
	local w, x, y, z = quatFromCF(c)
	if w < 0 then
		w, x, y, z = -w, -x, -y, -z
	end
	local ang = 2 * math.acos(math.clamp(w, -1, 1))
	local s = math.sqrt(math.max(1 - w * w, 0))
	if s < 1e-9 then
		return newV3(1, 0, 0), 0
	end
	return newV3(x / s, y / s, z / s), ang
end
CF.toAxisAngle = CF.ToAxisAngle
function CF.Orthonormalize(c)
	local x = newV3(c.r00, c.r10, c.r20).Unit
	local y = newV3(c.r01, c.r11, c.r21)
	y = (y - x * x:Dot(y)).Unit
	local z = x:Cross(y)
	return newCFRaw(c.x, c.y, c.z, x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z)
end
function CF.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	local ca, cb = { a:GetComponents() }, { b:GetComponents() }
	for i = 1, 12 do
		if math.abs(ca[i] - cb[i]) > eps then
			return false
		end
	end
	return true
end

for k, v in pairs(CF) do
	if string.sub(k, 1, 2) ~= "__" then
		CFmethods[k] = v
	end
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
	assert(isV3(pos) and isV3(vx) and isV3(vy), "CFrame.fromMatrix(Vector3, Vector3, Vector3, Vector3?)")
	vz = vz or vx:Cross(vy)
	return newCFRaw(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end

local function lookAt(at, target, up)
	assert(isV3(at) and isV3(target), "CFrame.lookAt(Vector3, Vector3, Vector3?)")
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

local function checkNumbers(name, ...)
	for i = 1, select("#", ...) do
		if type((select(i, ...))) ~= "number" then
			error(name .. ": argument " .. i .. " must be a number", 3)
		end
	end
end

CFrame = {
	new = function(...)
		local n = select("#", ...)
		local a, b = ...
		if n == 0 then
			return newCFRaw(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		end
		if isV3(a) then
			if b ~= nil then
				assert(isV3(b), "CFrame.new(Vector3, Vector3)")
				return lookAt(a, b)
			end
			return newCFRaw(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		end
		if n == 3 then
			checkNumbers("CFrame.new", ...)
			local x, y, z = ...
			return newCFRaw(x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		elseif n == 7 then
			checkNumbers("CFrame.new", ...)
			local x, y, z, qx, qy, qz, qw = ...
			return cfFromQuat(x, y, z, qw, qx, qy, qz)
		elseif n == 12 then
			checkNumbers("CFrame.new", ...)
			return newCFRaw(...)
		end
		error("CFrame.new: unsupported argument count " .. n, 2)
	end,
	Angles = function(rx, ry, rz)
		checkNumbers("CFrame.Angles", rx, ry, rz)
		return rotX(rx) * rotY(ry) * rotZ(rz)
	end,
	fromEulerAnglesXYZ = function(rx, ry, rz)
		checkNumbers("CFrame.fromEulerAnglesXYZ", rx, ry, rz)
		return rotX(rx) * rotY(ry) * rotZ(rz)
	end,
	fromEulerAnglesYXZ = function(rx, ry, rz)
		checkNumbers("CFrame.fromEulerAnglesYXZ", rx, ry, rz)
		return rotY(ry) * rotX(rx) * rotZ(rz)
	end,
	fromOrientation = function(rx, ry, rz)
		checkNumbers("CFrame.fromOrientation", rx, ry, rz)
		return rotY(ry) * rotX(rx) * rotZ(rz)
	end,
	fromEulerAngles = function(rx, ry, rz, order)
		checkNumbers("CFrame.fromEulerAngles", rx, ry, rz)
		local o = order and order.Name or "XYZ"
		local m = { X = rotX(rx), Y = rotY(ry), Z = rotZ(rz) }
		return m[string.sub(o, 1, 1)] * m[string.sub(o, 2, 2)] * m[string.sub(o, 3, 3)]
	end,
	fromAxisAngle = function(axis, a)
		assert(isV3(axis) and type(a) == "number", "CFrame.fromAxisAngle(Vector3, number)")
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
	lookAlong = function(at, dir, up)
		return lookAt(at, at + dir, up)
	end,
	fromMatrix = fromMatrix,
	identity = newCFRaw(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
}

---------------------------------------------------------------- Color3
local C3 = {}
TYPE_NAMES[C3] = "Color3"
local C3methods = {}
C3.__index = function(_, k)
	local m = C3methods[k]
	if m == nil then
		error("Color3 has no member " .. tostring(k), 2)
	end
	return m
end
C3.__newindex = immutable("Color3")
local function newC3(r, g, b)
	r, g, b = r or 0, g or 0, b or 0
	assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "Color3 expects numbers")
	return setmetatable({ R = r, G = g, B = b }, C3)
end
local function isC3(c)
	return type(c) == "table" and getmetatable(c) == C3
end
C3.__eq = function(a, b)
	return isC3(a) and isC3(b) and a.R == b.R and a.G == b.G and a.B == b.B
end
C3.__tostring = function(c)
	return string.format("%g, %g, %g", c.R, c.G, c.B)
end
function C3methods.Lerp(a, b, t)
	assert(isC3(b) and type(t) == "number", "Color3:Lerp(Color3, number)")
	return newC3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3methods.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h = h / 6
	end
	local s = mx > 0 and d / mx or 0
	return h, s, mx
end
function C3methods.ToHex(c)
	local function q(v)
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return string.format("%02x%02x%02x", q(c.R), q(c.G), q(c.B))
end
local function fromHSV(h, s, v)
	h = (h % 1) * 6
	local i = math.floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	if i == 0 then
		return newC3(v, t, p)
	elseif i == 1 then
		return newC3(q, v, p)
	elseif i == 2 then
		return newC3(p, v, t)
	elseif i == 3 then
		return newC3(p, q, v)
	elseif i == 4 then
		return newC3(t, p, v)
	end
	return newC3(v, p, q)
end
Color3 = {
	new = newC3,
	fromRGB = function(r, g, b)
		r, g, b = r or 0, g or 0, b or 0
		for _, v in ipairs({ r, g, b }) do
			if type(v) ~= "number" then
				error("Color3.fromRGB expects numbers", 2)
			end
			if v < -0.01 or v > 255.01 then
				mockWarn("Color3.fromRGB component out of range: " .. tostring(v))
			end
		end
		return newC3(r / 255, g / 255, b / 255)
	end,
	fromHSV = fromHSV,
	toHSV = function(c)
		return C3methods.ToHSV(c)
	end,
	fromHex = function(hex)
		hex = string.gsub(hex, "^#", "")
		assert(#hex == 6 or #hex == 3, "Color3.fromHex: bad hex string")
		if #hex == 3 then
			hex = string.gsub(hex, ".", "%0%0")
		end
		return newC3(tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255)
	end,
}
MOCK.isC3 = isC3

local BC = {}
TYPE_NAMES[BC] = "BrickColor"
BC.__index = function(b, k)
	if k == "Color" then
		return newC3(0.64, 0.64, 0.65)
	end
	error("BrickColor has no member " .. tostring(k), 2)
end
BrickColor = {
	new = function(n)
		return setmetatable({ Name = tostring(n) }, BC)
	end,
	White = function()
		return setmetatable({ Name = "White" }, BC)
	end,
}

---------------------------------------------------------------- Ranges and sequences
local NR = {}
TYPE_NAMES[NR] = "NumberRange"
NR.__index = strictIndex("NumberRange", {})
NR.__newindex = immutable("NumberRange")
NR.__eq = function(a, b)
	return getmetatable(b) == NR and a.Min == b.Min and a.Max == b.Max
end
NR.__tostring = function(r)
	return r.Min .. " " .. r.Max
end
NumberRange = {
	new = function(a, b)
		b = b or a
		assert(type(a) == "number" and type(b) == "number", "NumberRange.new expects numbers")
		if a > b then
			error("NumberRange: invalid range (min > max)", 2)
		end
		return setmetatable({ Min = a, Max = b }, NR)
	end,
}

local NSK = {}
TYPE_NAMES[NSK] = "NumberSequenceKeypoint"
NSK.__index = strictIndex("NumberSequenceKeypoint", {})
NSK.__newindex = immutable("NumberSequenceKeypoint")
NSK.__eq = function(a, b)
	return getmetatable(b) == NSK and a.Time == b.Time and a.Value == b.Value and a.Envelope == b.Envelope
end
NumberSequenceKeypoint = {
	new = function(t, v, e)
		assert(type(t) == "number" and type(v) == "number", "NumberSequenceKeypoint.new(time, value, envelope?)")
		assert(t >= 0 and t <= 1, "keypoint time out of range")
		return setmetatable({ Time = t, Value = v, Envelope = e or 0 }, NSK)
	end,
}
local function checkKeypoints(name, kps, mt)
	assert(#kps >= 2, name .. " needs at least 2 keypoints")
	assert(#kps <= 20, name .. " supports at most 20 keypoints")
	assert(kps[1].Time == 0 and kps[#kps].Time == 1, name .. " must start at 0 and end at 1")
	for i, k in ipairs(kps) do
		assert(getmetatable(k) == mt, name .. ": keypoint " .. i .. " has the wrong type")
		if i > 1 and k.Time < kps[i - 1].Time then
			error(name .. ": all keypoints must be ordered by time", 3)
		end
	end
end
local function seqEq(a, b)
	if getmetatable(a) ~= getmetatable(b) or #a.Keypoints ~= #b.Keypoints then
		return false
	end
	for i, k in ipairs(a.Keypoints) do
		if not (k == b.Keypoints[i]) then
			return false
		end
	end
	return true
end
local NS = {}
TYPE_NAMES[NS] = "NumberSequence"
NS.__index = strictIndex("NumberSequence", {})
NS.__newindex = immutable("NumberSequence")
NS.__eq = seqEq
NumberSequence = {
	new = function(a, b)
		if type(a) == "table" then
			checkKeypoints("NumberSequence", a, NSK)
			return setmetatable({ Keypoints = table.clone(a) }, NS)
		end
		assert(type(a) == "number" and (b == nil or type(b) == "number"), "NumberSequence.new expects numbers or keypoints")
		return setmetatable({ Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) } }, NS)
	end,
}
local CSK = {}
TYPE_NAMES[CSK] = "ColorSequenceKeypoint"
CSK.__index = strictIndex("ColorSequenceKeypoint", {})
CSK.__newindex = immutable("ColorSequenceKeypoint")
CSK.__eq = function(a, b)
	return getmetatable(b) == CSK and a.Time == b.Time and a.Value == b.Value
end
ColorSequenceKeypoint = {
	new = function(t, c)
		assert(type(t) == "number" and isC3(c), "ColorSequenceKeypoint.new(time, Color3)")
		assert(t >= 0 and t <= 1, "keypoint time out of range")
		return setmetatable({ Time = t, Value = c }, CSK)
	end,
}
local CS = {}
TYPE_NAMES[CS] = "ColorSequence"
CS.__index = strictIndex("ColorSequence", {})
CS.__newindex = immutable("ColorSequence")
CS.__eq = seqEq
ColorSequence = {
	new = function(a, b)
		if type(a) == "table" and not isC3(a) then
			checkKeypoints("ColorSequence", a, CSK)
			return setmetatable({ Keypoints = table.clone(a) }, CS)
		end
		assert(isC3(a) and (b == nil or isC3(b)), "ColorSequence.new expects Color3s or keypoints")
		return setmetatable({ Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } }, CS)
	end,
}

---------------------------------------------------------------- UDim / UDim2 / Rect
local UD = {}
TYPE_NAMES[UD] = "UDim"
UD.__index = strictIndex("UDim", {})
UD.__newindex = immutable("UDim")
local function isUD(v)
	return type(v) == "table" and getmetatable(v) == UD
end
local function newUD(s, o)
	s, o = s or 0, o or 0
	assert(type(s) == "number" and type(o) == "number", "UDim.new expects numbers")
	return setmetatable({ Scale = s, Offset = o }, UD)
end
UD.__eq = function(a, b)
	return isUD(a) and isUD(b) and a.Scale == b.Scale and a.Offset == b.Offset
end
UD.__add = function(a, b)
	return newUD(a.Scale + b.Scale, a.Offset + b.Offset)
end
UD.__sub = function(a, b)
	return newUD(a.Scale - b.Scale, a.Offset - b.Offset)
end
UD.__unm = function(a)
	return newUD(-a.Scale, -a.Offset)
end
UD.__tostring = function(u)
	return u.Scale .. ", " .. u.Offset
end
UDim = { new = newUD }

local UD2 = {}
TYPE_NAMES[UD2] = "UDim2"
local UD2methods = {}
UD2.__index = function(u, k)
	if k == "Width" then
		return rawget(u, "X")
	elseif k == "Height" then
		return rawget(u, "Y")
	end
	local m = UD2methods[k]
	if m == nil then
		error("UDim2 has no member " .. tostring(k), 2)
	end
	return m
end
UD2.__newindex = immutable("UDim2")
local function isUD2(v)
	return type(v) == "table" and getmetatable(v) == UD2
end
local function newUD2(xs, xo, ys, yo)
	if isUD(xs) then
		assert(isUD(xo), "UDim2.new(UDim, UDim)")
		return setmetatable({ X = xs, Y = xo }, UD2)
	end
	return setmetatable({ X = newUD(xs, xo), Y = newUD(ys, yo) }, UD2)
end
UD2.__eq = function(a, b)
	return isUD2(a) and isUD2(b) and a.X == b.X and a.Y == b.Y
end
UD2.__add = function(a, b)
	return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y }, UD2)
end
UD2.__sub = function(a, b)
	return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y }, UD2)
end
UD2.__unm = function(a)
	return setmetatable({ X = -a.X, Y = -a.Y }, UD2)
end
UD2.__tostring = function(u)
	return "{" .. tostring(u.X) .. "}, {" .. tostring(u.Y) .. "}"
end
function UD2methods.Lerp(a, b, t)
	local function l(x, y)
		return x + (y - x) * t
	end
	return newUD2(l(a.X.Scale, b.X.Scale), l(a.X.Offset, b.X.Offset), l(a.Y.Scale, b.Y.Scale), l(a.Y.Offset, b.Y.Offset))
end
UDim2 = {
	new = newUD2,
	fromScale = function(x, y)
		return newUD2(x, 0, y, 0)
	end,
	fromOffset = function(x, y)
		return newUD2(0, x, 0, y)
	end,
}
MOCK.isUD2 = isUD2

local RECT = {}
TYPE_NAMES[RECT] = "Rect"
RECT.__index = function(r, k)
	if k == "Width" then
		return r.Max.X - r.Min.X
	elseif k == "Height" then
		return r.Max.Y - r.Min.Y
	end
	error("Rect has no member " .. tostring(k), 2)
end
RECT.__newindex = immutable("Rect")
RECT.__eq = function(a, b)
	return getmetatable(b) == RECT and a.Min == b.Min and a.Max == b.Max
end
Rect = {
	new = function(a, b, c, d)
		if isV2(a) then
			return setmetatable({ Min = a, Max = b }, RECT)
		end
		return setmetatable({ Min = newV2(a or 0, b or 0), Max = newV2(c or 0, d or 0) }, RECT)
	end,
}

local RAY = {}
TYPE_NAMES[RAY] = "Ray"
local RAYmethods = {}
RAY.__index = function(r, k)
	if k == "Unit" then
		return setmetatable({ Origin = r.Origin, Direction = r.Direction.Unit }, RAY)
	end
	local m = RAYmethods[k]
	if m == nil then
		error("Ray has no member " .. tostring(k), 2)
	end
	return m
end
RAY.__newindex = immutable("Ray")
function RAYmethods.ClosestPoint(r, p)
	local d = r.Direction.Unit
	local t = math.max((p - r.Origin):Dot(d), 0)
	return r.Origin + d * t
end
function RAYmethods.Distance(r, p)
	return (p - RAYmethods.ClosestPoint(r, p)).Magnitude
end
Ray = {
	new = function(o, d)
		assert(isV3(o) and isV3(d), "Ray.new(Vector3, Vector3)")
		return setmetatable({ Origin = o, Direction = d }, RAY)
	end,
}

---------------------------------------------------------------- Misc value types
local TI = {}
TYPE_NAMES[TI] = "TweenInfo"
TI.__index = strictIndex("TweenInfo", {})
TI.__newindex = immutable("TweenInfo")

PhysicalProperties = {
	new = function(...)
		return { ... }
	end,
}
local FONT = {}
TYPE_NAMES[FONT] = "Font"
FONT.__index = strictIndex("Font", {})
FONT.__eq = function(a, b)
	return getmetatable(b) == FONT and a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style
end
Font = {
	new = function(family, weight, style)
		assert(type(family) == "string", "Font.new(family: string, weight?, style?)")
		return setmetatable({ Family = family, Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal }, FONT)
	end,
	fromEnum = function(e)
		return setmetatable({ Family = "rbxasset://fonts/families/" .. e.Name .. ".json", Weight = Enum.FontWeight.Regular, Style = Enum.FontStyle.Normal }, FONT)
	end,
	fromName = function(name, weight, style)
		return setmetatable({ Family = "rbxasset://fonts/families/" .. name .. ".json", Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal }, FONT)
	end,
	fromId = function(id, weight, style)
		return setmetatable({ Family = "rbxassetid://" .. tostring(id), Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal }, FONT)
	end,
}

local R3 = {}
TYPE_NAMES[R3] = "Region3"
R3.__index = function(r, k)
	local m = rawget(r, "__m")[k]
	if m == nil then
		error("Region3 has no member " .. tostring(k), 2)
	end
	return m
end
Region3 = {
	new = function(a, b)
		local fields = { Min = a, Max = b, Size = b - a, CFrame = CFrame.new((a + b) / 2) }
		function fields.ExpandToGrid(_, res)
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
		local r = setmetatable({ __m = fields }, R3)
		-- direct fields for speed (the terrain writer reads Min/Max a lot)
		rawset(r, "Min", a)
		rawset(r, "Max", b)
		return r
	end,
}

---------------------------------------------------------------- Random
local RNG = {}
TYPE_NAMES[RNG] = "Random"
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
function RNG:Clone()
	return setmetatable({ s = self.s }, RNG)
end
Random = {
	new = function(seed)
		return setmetatable({ s = math.floor(math.abs(seed or 1)) % 2147483648 + 1 }, RNG)
	end,
}

---------------------------------------------------------------- Enum
-- Items are "Name" (value = previous + 1, from 0) or "Name=value".
local ENUM_DEFS = {
	Material = "Plastic=256 SmoothPlastic=272 Neon=288 Wood=512 WoodPlanks=528 Marble=784 Slate=800 Concrete=816 Granite=832 Brick=848 Pebble=864 Cobblestone=880 CorrodedMetal=1040 DiamondPlate=1056 Foil=1072 Metal=1088 Grass=1280 LeafyGrass=1284 Sand=1296 Fabric=1312 Ice=1536 Glass=1568 ForceField=1584 Basalt=788 Ground=1300 CrackedLava=804 Asphalt=1376 Limestone=820 Mud=1304 Pavement=836 Plaster=849 Rock=896 Salt=1392 Sandstone=1360 Snow=1328 Glacier=1552 Water=2048 Air=1792 Cardboard=1286 Carpet=1287 CeramicTiles=1288 ClayRoofTiles=1289 RoofShingles=1290 Leather=1291 Rubber=1292",
	PartType = "Ball Block Cylinder Wedge CornerWedge",
	SurfaceType = "Smooth SmoothNoOutlines Studs Inlet Universal",
	NormalId = "Right Top Back Left Bottom Front",
	MeshType = "Head Torso Wedge Prism Pyramid ParallelRamp RightAngleRamp CornerWedge Brick Sphere Cylinder FileMesh",
	CollisionFidelity = "Default Hull Box PreciseConvexDecomposition",
	RenderFidelity = "Automatic Precise Performance",
	ModelStreamingMode = "Default Atomic Persistent PersistentPerPlayer Nonatomic",
	Technology = "Legacy Voxel Compatibility ShadowMap Future Unified",
	LightingStyle = "Realistic Soft",
	EasingStyle = "Linear Sine Back Quad Quart Quint Bounce Elastic Exponential Circular Cubic",
	EasingDirection = "In Out InOut",
	PlaybackState = "Begin Delayed Playing Paused Completed Cancelled",
	ParticleEmitterShape = "Box Sphere Cylinder Disc",
	ParticleEmitterShapeStyle = "Volume Surface",
	ParticleEmitterShapeInOut = "Outward Inward InAndOut",
	ParticleOrientation = "FacingCamera FacingCameraWorldUp VelocityParallel VelocityPerpendicular",
	ParticleFlipbookLayout = "None Grid2x2 Grid4x4 Grid8x8 Custom",
	ParticleFlipbookMode = "Loop OneShot PingPong Random",
	Font = "Legacy Arial ArialBold SourceSans SourceSansBold SourceSansLight SourceSansItalic Bodoni Garamond Cartoon Code Highway SciFi Arcade Fantasy Antique SourceSansSemibold Gotham GothamMedium GothamBold GothamBlack AmaticSC Bangers Creepster DenkOne Fondamento FredokaOne GrenzeGotisch IndieFlower JosefinSans Jura Kalam LuckiestGuy Merriweather Michroma Nunito Oswald PatrickHand PermanentMarker Roboto RobotoCondensed RobotoMono Sarpanch SpecialElite TitilliumWeb Ubuntu BuilderSans BuilderSansMedium BuilderSansBold BuilderSansExtraBold Arimo ArimoBold Unknown",
	FontWeight = "Thin=100 ExtraLight=200 Light=300 Regular=400 Medium=500 SemiBold=600 Bold=700 ExtraBold=800 Heavy=900",
	FontStyle = "Normal Italic",
	StreamingIntegrityMode = "Default Disabled MinimumRadiusPause PauseOutsideLoadedArea",
	StreamOutBehavior = "Default LowMemory Opportunistic",
	LevelOfDetailSetting = "Automatic StreamingMesh Disabled",
	ModelLevelOfDetail = "Automatic StreamingMesh Disabled",
	KeyCode = "Unknown=0 Backspace=8 Tab=9 Clear=12 Return=13 Pause=19 Escape=27 Space=32 QuotedDouble=34 Hash=35 Dollar=36 Percent=37 Ampersand=38 Quote=39 LeftParenthesis=40 RightParenthesis=41 Asterisk=42 Plus=43 Comma=44 Minus=45 Period=46 Slash=47 Zero=48 One Two Three Four Five Six Seven Eight Nine Colon=58 Semicolon=59 LessThan=60 Equals=61 GreaterThan=62 Question=63 At=64 LeftBracket=91 BackSlash=92 RightBracket=93 Caret=94 Underscore=95 Backquote=96 A=97 B C D E F G H I J K L M N O P Q R S T U V W X Y Z LeftCurly=123 Pipe=124 RightCurly=125 Tilde=126 Delete=127 KeypadZero=256 KeypadOne KeypadTwo KeypadThree KeypadFour KeypadFive KeypadSix KeypadSeven KeypadEight KeypadNine KeypadPeriod KeypadDivide KeypadMultiply KeypadMinus KeypadPlus KeypadEnter KeypadEquals Up=273 Down Right Left Insert Home End PageUp PageDown F1=282 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 F13 F14 F15 NumLock=300 CapsLock ScrollLock RightShift LeftShift RightControl LeftControl RightAlt LeftAlt RightMeta LeftMeta LeftSuper RightSuper ButtonX=1000 ButtonY ButtonA ButtonB ButtonR1 ButtonL1 ButtonR2 ButtonL2 ButtonR3 ButtonL3 ButtonStart ButtonSelect DPadLeft DPadRight DPadUp DPadDown Thumbstick1 Thumbstick2",
	UserInputType = "MouseButton1 MouseButton2 MouseButton3 MouseWheel MouseMovement Touch Keyboard Focus Accelerometer Gyro Gamepad1 Gamepad2 Gamepad3 Gamepad4 Gamepad5 Gamepad6 Gamepad7 Gamepad8 TextInput InputMethod None",
	UserInputState = "Begin Change End Cancel None",
	ContextActionResult = "Sink Pass",
	ContextActionPriority = "Low=1000 Medium=2000 Default=2000 High=3000",
	MouseBehavior = "Default LockCenter LockCurrentPosition",
	CameraType = "Fixed Attach Watch Track Follow Custom Scriptable Orbital",
	CameraMode = "Classic LockFirstPerson",
	FieldOfViewMode = "Vertical Diagonal MaxAxis",
	RenderPriority = "First=0 Input=100 Camera=200 Character=300 Last=2000",
	HumanoidRigType = "R6 R15",
	HumanoidStateType = "FallingDown=0 Ragdoll=1 GettingUp=2 Jumping=3 Swimming=4 Freefall=5 Flying=6 Landed=7 Running=8 RunningNoPhysics=10 StrafingNoPhysics=11 Climbing=12 Seated=13 PlatformStanding=14 Dead=15 Physics=16 None=18",
	HumanoidDisplayDistanceType = "Viewer Subject None",
	HumanoidHealthDisplayType = "DisplayWhenDamaged AlwaysOn AlwaysOff",
	AnimationPriority = "Idle=0 Movement=1 Action=2 Action2=3 Action3=4 Action4=5 Core=1000",
	HighlightDepthMode = "AlwaysOnTop Occluded",
	ZIndexBehavior = "Global Sibling",
	RunContext = "Legacy Server Client Plugin",
	TextureMode = "Stretch Wrap Static",
	TextXAlignment = "Left Right Center",
	TextYAlignment = "Top Center Bottom",
	TextTruncate = "None AtEnd SplitWord",
	TextDirection = "Auto LeftToRight RightToLeft",
	ScaleType = "Stretch Slice Tile Fit Crop",
	ResamplerMode = "Default Pixelated",
	SizeConstraint = "RelativeXY RelativeXX RelativeYY",
	AutomaticSize = "None X Y XY",
	BorderMode = "Outline Middle Inset",
	FrameStyle = "Custom ChatBlue RobloxSquare RobloxRound ChatGreen ChatRed DropShadow",
	ButtonStyle = "Custom RobloxButtonDefault RobloxButton RobloxRoundButton RobloxRoundDefaultButton RobloxRoundDropdownButton",
	AspectType = "FitWithinMaxSize ScaleWithParentSize",
	DominantAxis = "Width Height",
	ApplyStrokeMode = "Contextual Border",
	LineJoinMode = "Round Bevel Miter",
	ScreenInsets = "None DeviceSafeInsets CoreUISafeInsets TopbarSafeInsets",
	SafeAreaCompatibility = "None FullscreenExtension",
	ScreenOrientation = "LandscapeLeft LandscapeRight LandscapeSensor Portrait Sensor",
	SortOrder = "Name Custom LayoutOrder",
	FillDirection = "Horizontal Vertical",
	HorizontalAlignment = "Center Left Right",
	VerticalAlignment = "Center Top Bottom",
	CoreGuiType = "PlayerList Health Backpack Chat All EmotesMenu SelfView Captures",
	RaycastFilterType = "Exclude Include Blacklist=0 Whitelist=1",
	RollOffMode = "Inverse Linear InverseTapered LinearSquare",
	ReverbType = "NoReverb GenericReverb PaddedCell Room Bathroom LivingRoom StoneRoom Auditorium ConcertHall Cave Arena Hangar CarpettedHallway Hallway StoneCorridor Alley Forest City Mountains Quarry Plain ParkingLot SewerPipe UnderWater",
	AlphaMode = "Overlay Transparency TintMask",
	SurfaceGuiSizingMode = "FixedSize PixelsPerStud",
	RotationOrder = "XYZ XZY YZX YXZ ZXY ZYX",
	AssetFetchStatus = "Success Failure None Loading TimedOut",
	BulkMoveMode = "FireAllEvents FireCFrameChanged",
	AccessoryType = "Unknown Hat Hair Face Neck Shoulder Front Back Waist TShirt Shirt Pants Jacket Sweater Shorts LeftShoe RightShoe DressSkirt Eyebrow Eyelash",
	DevCameraOcclusionMode = "Zoom Invisicam",
	Limb = "Head Torso LeftArm RightArm LeftLeg RightLeg Unknown",
}
local enumTypes = {}
local ENUMITEM = {}
TYPE_NAMES[ENUMITEM] = "EnumItem"
local ENUMTYPE = {}
TYPE_NAMES[ENUMTYPE] = "Enum"
local ENUMITEM_METHODS = {
	IsA = function(item, name)
		return rawget(item, "__t") == name
	end,
}
ENUMITEM.__index = function(item, k)
	if k == "EnumType" then
		return enumTypes[rawget(item, "__t")]
	end
	local m = ENUMITEM_METHODS[k]
	if m == nil then
		error(tostring(item) .. " has no member " .. tostring(k), 2)
	end
	return m
end
ENUMITEM.__newindex = immutable("EnumItem")
ENUMITEM.__tostring = function(item)
	return "Enum." .. rawget(item, "__t") .. "." .. rawget(item, "Name")
end
local function isEnum(v, typeName)
	return type(v) == "table" and getmetatable(v) == ENUMITEM and (typeName == nil or rawget(v, "__t") == typeName)
end
MOCK.isEnum = isEnum

local function makeEnumType(typeName)
	local spec = ENUM_DEFS[typeName]
	if not spec then
		return nil
	end
	local items, list, byValue = {}, {}, {}
	local nextValue = 0
	for word in string.gmatch(spec, "%S+") do
		local name, value = string.match(word, "^([%w_]+)=(%-?%d+)$")
		if name then
			value = tonumber(value)
		else
			name, value = word, nextValue
		end
		nextValue = value + 1
		local item = setmetatable({ Name = name, Value = value, __t = typeName }, ENUMITEM)
		items[name] = item
		table.insert(list, item)
		if byValue[value] == nil then
			byValue[value] = item
		end
	end
	local methods = {
		GetEnumItems = function()
			return table.clone(list)
		end,
		FromName = function(_, n)
			return items[n]
		end,
		FromValue = function(_, v)
			return byValue[v]
		end,
	}
	local t = setmetatable({ __items = items, __name = typeName }, ENUMTYPE)
	rawset(t, "__methods", methods)
	return t
end
ENUMTYPE.__index = function(t, name)
	local it = rawget(t, "__items")[name]
	if it then
		return it
	end
	local m = rawget(t, "__methods")[name]
	if m then
		return m
	end
	error("Unknown enum item Enum." .. rawget(t, "__name") .. "." .. tostring(name), 2)
end
ENUMTYPE.__newindex = immutable("Enum")
ENUMTYPE.__tostring = function(t)
	return rawget(t, "__name")
end
local ENUMS = {}
TYPE_NAMES[ENUMS] = "Enums"
ENUMS.__index = function(_, typeName)
	if typeName == "GetEnums" then
		return function()
			local out = {}
			for n in pairs(ENUM_DEFS) do
				table.insert(out, Enum[n])
			end
			return out
		end
	end
	local t = enumTypes[typeName]
	if t then
		return t
	end
	t = makeEnumType(typeName)
	if not t then
		error("Unknown enum type Enum." .. tostring(typeName), 2)
	end
	enumTypes[typeName] = t
	return t
end
ENUMS.__newindex = immutable("Enum")
Enum = setmetatable({}, ENUMS)

-- Coerces a value for an enum-typed property like Roblox does (item, item name or number).
local function toEnum(typeName, v)
	if isEnum(v, typeName) then
		return v
	end
	local et = Enum[typeName]
	if type(v) == "string" then
		return rawget(et, "__items")[v]
	elseif type(v) == "number" then
		return rawget(et, "__methods").FromValue(et, v)
	end
	return nil
end
MOCK.toEnum = toEnum

TweenInfo = {
	new = function(time, style, direction, repeatCount, reverses, delayTime)
		time = time or 1
		style = style or Enum.EasingStyle.Quad
		direction = direction or Enum.EasingDirection.Out
		repeatCount = repeatCount or 0
		reverses = reverses or false
		delayTime = delayTime or 0
		assert(type(time) == "number" and time >= 0, "TweenInfo.new: time must be a non-negative number")
		assert(isEnum(style, "EasingStyle"), "TweenInfo.new: easingStyle must be Enum.EasingStyle")
		assert(isEnum(direction, "EasingDirection"), "TweenInfo.new: easingDirection must be Enum.EasingDirection")
		assert(type(repeatCount) == "number", "TweenInfo.new: repeatCount must be a number")
		assert(type(reverses) == "boolean", "TweenInfo.new: reverses must be a boolean")
		assert(type(delayTime) == "number", "TweenInfo.new: delayTime must be a number")
		return setmetatable({
			Time = time,
			EasingStyle = style,
			EasingDirection = direction,
			RepeatCount = repeatCount,
			Reverses = reverses,
			DelayTime = delayTime,
		}, TI)
	end,
}

---------------------------------------------------------------- Scheduler (task library)
-- Threads run in a "context": "edit" (default: Studio edit mode, both IsClient and
-- IsServer are true), "client" or "server". Connections and waiting threads keep the
-- context they were created in.
local curCtx = "edit"
MOCK.context = function()
	return curCtx
end
local function reportError(err, co)
	local msg = tostring(err)
	local tb = co and debug.traceback(co, msg) or msg
	table.insert(MOCK.errors, tb)
	print("MOCKERROR " .. tb)
end
MOCK.reportError = reportError

local function resumeThread(co, ctx, ...)
	if coroutine.status(co) ~= "suspended" then
		return false
	end
	local prev = curCtx
	curCtx = ctx or prev
	local ok, err = coroutine.resume(co, ...)
	curCtx = prev
	if not ok then
		reportError(err, co)
	end
	return ok
end
local function spawnThread(fn, ctx, ...)
	local co = coroutine.create(fn)
	resumeThread(co, ctx or curCtx, ...)
	return co
end
MOCK.spawn = spawnThread
-- Runs fn(...) in a new thread in the given context ("client", "server" or "edit").
function MOCK.runInContext(ctx, fn, ...)
	assert(ctx == "client" or ctx == "server" or ctx == "edit", "bad context " .. tostring(ctx))
	return spawnThread(fn, ctx, ...)
end

local waiting = {} -- { co=, wake=, ctx=, start= } task.wait / task.delay
local deferred = {} -- { co=, ctx=, args= }
-- The luau CLI runs the main chunk in a yieldable coroutine; yielding it would end the
-- program, so the thread that loaded the mock counts as "main" (never yields).
local mainThread = coroutine.running()
MOCK.mainThread = mainThread
local function canYield()
	return coroutine.running() ~= mainThread and coroutine.isyieldable()
end

local function flushDeferred()
	local guard = 0
	while #deferred > 0 do
		guard += 1
		if guard > 10000 then
			reportError("task.defer: more than 10000 re-entrant deferred resumptions (infinite defer loop?)")
			deferred = {}
			break
		end
		local q = deferred
		deferred = {}
		for _, d in ipairs(q) do
			resumeThread(d.co, d.ctx, table.unpack(d.args, 1, d.args.n))
		end
	end
end
MOCK.flushDeferred = flushDeferred

local function resumeWaiting()
	local due, keep = {}, {}
	local now = MOCK.clock + 1e-9
	for _, w in ipairs(waiting) do
		if w.wake <= now then
			table.insert(due, w)
		else
			table.insert(keep, w)
		end
	end
	if #due == 0 then
		return
	end
	waiting = keep
	table.sort(due, function(a, b)
		if a.wake ~= b.wake then
			return a.wake < b.wake
		end
		return a.seq < b.seq
	end)
	for _, w in ipairs(due) do
		if w.args then
			resumeThread(w.co, w.ctx, table.unpack(w.args, 1, w.args.n))
		else
			resumeThread(w.co, w.ctx, MOCK.clock - w.start)
		end
	end
end
local waitSeq = 0
local function schedule(co, delay, args)
	waitSeq += 1
	table.insert(waiting, { co = co, wake = MOCK.clock + delay, ctx = curCtx, start = MOCK.clock, args = args, seq = waitSeq })
end
MOCK.pendingThreads = function()
	return #waiting, #deferred
end

local function toThread(f)
	if type(f) == "thread" then
		return f
	end
	if type(f) ~= "function" then
		error("task: expected a function or thread, got " .. type(f), 3)
	end
	return coroutine.create(f)
end

task = {
	wait = function(t)
		if t ~= nil and type(t) ~= "number" then
			error("task.wait expects a number", 2)
		end
		t = t or 0
		if not canYield() then
			-- main thread (e.g. the generator running as a plugin/command): don't block
			MOCK.waits = (MOCK.waits or 0) + 1
			return t
		end
		schedule(coroutine.running(), t, nil)
		return coroutine.yield()
	end,
	spawn = function(f, ...)
		local co = toThread(f)
		resumeThread(co, curCtx, ...)
		return co
	end,
	defer = function(f, ...)
		local co = toThread(f)
		table.insert(deferred, { co = co, ctx = curCtx, args = table.pack(...) })
		return co
	end,
	delay = function(t, f, ...)
		assert(type(t) == "number", "task.delay expects a number")
		local co = toThread(f)
		schedule(co, t, table.pack(...))
		return co
	end,
	cancel = function(co)
		assert(type(co) == "thread", "task.cancel expects a thread")
		for i = #waiting, 1, -1 do
			if waiting[i].co == co then
				table.remove(waiting, i)
			end
		end
		for i = #deferred, 1, -1 do
			if deferred[i].co == co then
				table.remove(deferred, i)
			end
		end
		if coroutine.status(co) == "suspended" then
			coroutine.close(co)
		end
	end,
	synchronize = function() end,
	desynchronize = function() end,
}
wait = task.wait
delay = task.delay
spawn = function(f)
	return task.defer(f)
end
shared = shared or {}
time = function()
	return MOCK.clock
end
elapsedTime = time
tick = function()
	return 1760000000 + MOCK.clock
end
-- Makes os.clock() return the simulated clock (deterministic frame-by-frame runs).
-- MOCK.realClock stays the real CPU clock.
function MOCK.useFakeClock(on)
	if on == false then
		os = MOCK.__realOs or os
		return
	end
	MOCK.__realOs = MOCK.__realOs or os
	local real = MOCK.__realOs
	os = setmetatable({
		clock = function()
			return MOCK.clock
		end,
	}, { __index = real })
end

local realWarn = warn or print
function warn(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	table.insert(MOCK.warnLog, table.concat(parts, " "))
	realWarn("[warn]", ...)
end

---------------------------------------------------------------- Signals
local SIGNAL = {}
TYPE_NAMES[SIGNAL] = "RBXScriptSignal"
local CONN = {}
TYPE_NAMES[CONN] = "RBXScriptConnection"
local SIGNAL_METHODS = {}
SIGNAL.__index = function(s, k)
	local m = SIGNAL_METHODS[k]
	if m == nil then
		error("RBXScriptSignal " .. tostring(rawget(s, "__name")) .. " has no member " .. tostring(k), 2)
	end
	return m
end
SIGNAL.__newindex = immutable("RBXScriptSignal")
SIGNAL.__tostring = function(s)
	return "Signal " .. tostring(rawget(s, "__name"))
end
local function disconnect(c)
	if not rawget(c, "Connected") then
		return
	end
	rawset(c, "Connected", false)
	local s = rawget(c, "__sig")
	local list = rawget(s, "__conns")
	for i, x in ipairs(list) do
		if x == c then
			table.remove(list, i)
			break
		end
	end
end
CONN.__index = function(c, k)
	if k == "Disconnect" or k == "disconnect" then
		return disconnect
	end
	error("RBXScriptConnection has no member " .. tostring(k), 2)
end
CONN.__newindex = immutable("RBXScriptConnection")

local function newSignal(name, ctxRule)
	-- ctxRule: nil, "client" (connect only from the client) or "server"
	return setmetatable({ __name = name, __conns = {}, __waiters = nil, __ctx = ctxRule }, SIGNAL)
end
MOCK.newSignal = newSignal
local function checkSignalCtx(s)
	local rule = rawget(s, "__ctx")
	if rule == "client" and curCtx == "server" then
		error(rawget(s, "__name") .. " can only be used from the client (LocalScript)", 3)
	elseif rule == "server" and curCtx == "client" then
		error(rawget(s, "__name") .. " can only be used on the server", 3)
	end
end
local function connect(s, fn, once)
	if type(fn) ~= "function" then
		error("Attempt to connect failed: Passed value is not a function", 3)
	end
	checkSignalCtx(s)
	local c = setmetatable({ __sig = s, __fn = fn, __ctx = curCtx, __once = once, Connected = true }, CONN)
	table.insert(rawget(s, "__conns"), c)
	return c
end
function SIGNAL_METHODS.Connect(s, fn)
	return connect(s, fn, false)
end
SIGNAL_METHODS.connect = SIGNAL_METHODS.Connect
SIGNAL_METHODS.ConnectParallel = SIGNAL_METHODS.Connect
function SIGNAL_METHODS.Once(s, fn)
	return connect(s, fn, true)
end
function SIGNAL_METHODS.Wait(s)
	if not canYield() then
		error("Mock: " .. tostring(rawget(s, "__name")) .. ":Wait() on the main thread would hang (run it in a coroutine)", 2)
	end
	checkSignalCtx(s)
	local w = rawget(s, "__waiters")
	if not w then
		w = {}
		rawset(s, "__waiters", w)
	end
	table.insert(w, { co = coroutine.running(), ctx = curCtx })
	return coroutine.yield()
end
SIGNAL_METHODS.wait = SIGNAL_METHODS.Wait

local function fire(s, ...)
	local conns = rawget(s, "__conns")
	local waiters = rawget(s, "__waiters")
	if #conns == 0 and not waiters then
		return
	end
	if #conns > 0 then
		local snapshot = table.clone(conns)
		for _, c in ipairs(snapshot) do
			if rawget(c, "Connected") then
				if rawget(c, "__once") then
					disconnect(c)
				end
				spawnThread(rawget(c, "__fn"), rawget(c, "__ctx"), ...)
			end
		end
	end
	if waiters then
		rawset(s, "__waiters", nil)
		for _, w in ipairs(waiters) do
			resumeThread(w.co, w.ctx, ...)
		end
	end
end
MOCK.fire = fire
local function disconnectAll(s)
	for _, c in ipairs(table.clone(rawget(s, "__conns"))) do
		disconnect(c)
	end
end
-- Number of live connections of a signal (leak checks in drivers).
function MOCK.connectionCount(s)
	return #rawget(s, "__conns")
end

---------------------------------------------------------------- Instances: classes
--[[
Class specs (def(name, spec)):
	base      parent class
	props     { Name = type }   writable properties; type is "any", "number", "int", "boolean",
	          "string", a value type name ("Vector3", "CFrame", "Color3", "UDim2", ...),
	          "Enum:<Type>", "Instance" or "Instance:<Class>" (nil always allowed for refs)
	ro        { Name = type }   read-only properties (value from defaults or a getter)
	defaults  { Name = value }
	get       { Name = fn(o) }  computed getters
	set       { Name = fn(o, v, k) } custom setters (called after type checks, must store)
	methods   { Name = fn }
	events    "A B C"
	eventCtx  { Name = "client" | "server" }
	init      fn(o)  on Instance.new (not on Clone)
	register  fn(o)  on Instance.new and Clone (registries)
	abstract / notCreatable / service / permissive
]]
local RAW_DEFS = {}
local CLASS = {}
local function def(name, spec)
	RAW_DEFS[name] = spec
end
MOCK.defClass = def

local instMeta = {}
TYPE_NAMES[instMeta] = "Instance"
local function isInstance(v)
	return type(v) == "table" and getmetatable(v) == instMeta
end
MOCK.isInstance = isInstance

local CHECKERS = {}
local function simple(pred, typeName)
	return function(v)
		if pred(v) then
			return true, v
		end
		return false, typeName
	end
end
CHECKERS.number = function(v)
	if type(v) == "number" then
		if v ~= v then
			return false, "number (got NaN)"
		end
		return true, v
	end
	return false, "number"
end
CHECKERS.int = CHECKERS.number
CHECKERS.boolean = simple(function(v)
	return type(v) == "boolean"
end, "boolean")
CHECKERS.string = function(v)
	if type(v) == "string" then
		return true, v
	elseif type(v) == "number" then
		return true, tostring(v)
	end
	return false, "string"
end
CHECKERS.Vector3 = simple(isV3, "Vector3")
CHECKERS.Vector2 = simple(isV2, "Vector2")
CHECKERS.CFrame = simple(isCF, "CFrame")
CHECKERS.Color3 = simple(isC3, "Color3")
for _, tn in ipairs({ "UDim", "UDim2", "NumberSequence", "ColorSequence", "NumberRange", "Rect", "Font", "BrickColor", "TweenInfo" }) do
	CHECKERS[tn] = simple(function(v)
		return typeof(v) == tn
	end, tn)
end
CHECKERS.Function = simple(function(v)
	return v == nil or type(v) == "function"
end, "function")
local checkerCache = {}
local function checkerFor(t)
	if t == "any" or t == true then
		return true
	end
	local c = checkerCache[t]
	if c then
		return c
	end
	if string.sub(t, 1, 5) == "Enum:" then
		local en = string.sub(t, 6)
		c = function(v)
			local item = toEnum(en, v)
			if item == nil then
				return false, "Enum." .. en
			end
			return true, item
		end
	elseif t == "Instance" or string.sub(t, 1, 9) == "Instance:" then
		local cls = string.sub(t, 10)
		c = function(v)
			if v == nil then
				return true, nil
			end
			if not isInstance(v) then
				return false, t
			end
			if cls ~= "" and not v:IsA(cls) then
				return false, cls
			end
			return true, v
		end
	else
		c = CHECKERS[t]
		if not c then
			error("Mock: unknown property type " .. tostring(t))
		end
	end
	checkerCache[t] = c
	return c
end

local function resolve(name)
	local c = CLASS[name]
	if c then
		return c
	end
	local spec = RAW_DEFS[name]
	if not spec then
		return nil
	end
	local base = spec.base and resolve(spec.base)
	if spec.base and not base then
		error("Mock: class " .. name .. " has unknown base " .. spec.base)
	end
	c = {
		name = name,
		ancestors = {},
		props = {},
		ro = {},
		defaults = {},
		get = {},
		set = {},
		methods = {},
		events = {},
		eventCtx = {},
		init = {},
		register = {},
		onParent = {},
	}
	if base then
		for _, field in ipairs({ "ancestors", "props", "ro", "defaults", "get", "set", "methods", "events", "eventCtx" }) do
			for k, v in pairs(base[field]) do
				c[field][k] = v
			end
		end
		for _, field in ipairs({ "init", "register", "onParent" }) do
			for _, f in ipairs(base[field]) do
				table.insert(c[field], f)
			end
		end
		c.permissive = base.permissive
	end
	c.ancestors[name] = true
	if spec.props then
		for k, t in pairs(spec.props) do
			if type(k) == "number" then
				c.props[t] = true -- legacy list: any type
				c.ro[t] = nil
			else
				c.props[k] = checkerFor(t)
				c.ro[k] = nil
			end
		end
	end
	if spec.ro then
		for k in pairs(spec.ro) do
			c.ro[k] = true
			c.props[k] = nil
		end
	end
	for _, field in ipairs({ "defaults", "get", "set", "methods", "eventCtx" }) do
		if spec[field] then
			for k, v in pairs(spec[field]) do
				c[field][k] = v
			end
		end
	end
	if spec.events then
		for e in string.gmatch(spec.events, "%S+") do
			c.events[e] = true
		end
	end
	for _, field in ipairs({ "init", "register", "onParent" }) do
		if spec[field] then
			table.insert(c[field], spec[field])
		end
	end
	if spec.permissive ~= nil then
		c.permissive = spec.permissive
	end
	c.spec = spec
	c.abstract = spec.abstract
	c.notCreatable = spec.notCreatable
	c.service = spec.service
	CLASS[name] = c
	return c
end
MOCK.classDef = resolve

local function className(o)
	return rawget(o, "__class")
end
local function defOf(o)
	return rawget(o, "__def")
end
local function isA(cls, query)
	if cls == query or query == "Instance" then
		return true
	end
	local c = resolve(cls)
	return c ~= nil and c.ancestors[query] == true
end
local function isPart(o)
	return defOf(o).ancestors.BasePart == true
end
MOCK.isA = isA

-- tree-event listeners exist? (keeps reparenting cheap for the generator)
local treeListeners = 0
local function getSignal(o, name)
	local sig = rawget(o, "__sig")
	if not sig then
		sig = {}
		rawset(o, "__sig", sig)
	end
	local s = sig[name]
	if not s then
		local c = defOf(o)
		s = newSignal(tostring(rawget(o, "__props").Name) .. "." .. name, c.eventCtx[name])
		sig[name] = s
		if name == "ChildAdded" or name == "ChildRemoved" or name == "DescendantAdded" or name == "DescendantRemoving" or name == "AncestryChanged" then
			treeListeners += 1
		end
	end
	return s
end
MOCK.signal = getSignal
local function fireIf(o, name, ...)
	local sig = rawget(o, "__sig")
	if sig then
		local s = sig[name]
		if s then
			fire(s, ...)
		end
	end
end
MOCK.fireEvent = fireIf

local function changed(o, k, v)
	local sig = rawget(o, "__sig")
	if not sig then
		return
	end
	local s = sig.Changed
	if s then
		if defOf(o).ancestors.ValueBase then
			if k == "Value" then
				fire(s, v)
			end
		else
			fire(s, k)
		end
	end
	s = sig["prop:" .. k]
	if s then
		fire(s)
	end
end

local Inst = {} -- Instance methods

instMeta.__index = function(o, k)
	local props = rawget(o, "__props")
	local v = props[k]
	if v ~= nil then
		return v
	end
	local c = rawget(o, "__def")
	local g = c.get[k]
	if g then
		return g(o)
	end
	v = c.defaults[k]
	if v ~= nil then
		return v
	end
	v = c.methods[k]
	if v ~= nil then
		return v
	end
	if c.events[k] then
		return getSignal(o, k)
	end
	if c.props[k] ~= nil or c.ro[k] ~= nil then
		return nil -- property without a value (properties win over children, like Roblox)
	end
	-- child lookup like Roblox (o.ChildName)
	for _, ch in ipairs(rawget(o, "__children")) do
		if rawget(ch, "__props").Name == k then
			return ch
		end
	end
	if c.permissive then
		return nil
	end
	error(tostring(props.Name) .. " is not a valid member of " .. c.name .. ' "' .. Inst.GetFullName(o) .. '"', 2)
end

instMeta.__newindex = function(o, k, v)
	local c = rawget(o, "__def")
	local chk = c.props[k]
	if chk == nil then
		if c.ro[k] or c.get[k] then
			error("Mock: Unable to assign property " .. tostring(k) .. ". Property is read only (" .. c.name .. ")", 2)
		elseif c.events[k] or c.methods[k] then
			error("Mock: " .. c.name .. "." .. tostring(k) .. " cannot be assigned to", 2)
		elseif c.permissive then
			rawget(o, "__props")[k] = v
			return
		end
		error("Mock: " .. c.name .. " has no property '" .. tostring(k) .. "'", 2)
	end
	if chk ~= true then
		local ok, cv = chk(v)
		if not ok then
			error("Mock: invalid value for " .. c.name .. "." .. tostring(k) .. " (" .. tostring(cv) .. " expected, got " .. typeof(v) .. ")", 2)
		end
		v = cv
	end
	local setter = c.set[k]
	if setter then
		setter(o, v, k)
		return
	end
	local props = rawget(o, "__props")
	local old = props[k]
	props[k] = v
	if old ~= v and rawget(o, "__sig") then
		changed(o, k, v)
	end
end
-- store + Changed for custom setters
local function store(o, k, v)
	local props = rawget(o, "__props")
	local old = props[k]
	props[k] = v
	if old ~= v and rawget(o, "__sig") then
		changed(o, k, v)
	end
end
MOCK.store = store

instMeta.__tostring = function(o)
	return tostring(rawget(o, "__props").Name)
end

local function internal(o)
	local t = rawget(o, "__int")
	if not t then
		t = {}
		rawset(o, "__int", t)
	end
	return t
end
MOCK.internal = internal

local function makeInstance(c, parent)
	MOCK.instanceCount += 1
	MOCK.classCounts[c.name] = (MOCK.classCounts[c.name] or 0) + 1
	local o = setmetatable({ __class = c.name, __def = c, __props = { Name = c.name }, __children = {}, __attrs = {} }, instMeta)
	for _, f in ipairs(c.init) do
		f(o)
	end
	for _, f in ipairs(c.register) do
		f(o)
	end
	if parent ~= nil then
		o.Parent = parent
	end
	return o
end

local function newInstance(cls, parent)
	if type(cls) ~= "string" then
		error("Instance.new expects a class name", 2)
	end
	local c = resolve(cls)
	if not c then
		error("Mock: Instance.new of unsupported class " .. tostring(cls), 2)
	end
	if c.abstract or c.service or c.notCreatable then
		error('Unable to create an Instance of type "' .. cls .. '"', 2)
	end
	return makeInstance(c, parent)
end
Instance = {
	new = newInstance,
	fromExisting = function(o)
		local c = Inst.Clone(o)
		return c
	end,
}

local function children(o)
	return rawget(o, "__children")
end
local function parentOf(o)
	return rawget(rawget(o, "__props"), "Parent")
end

local function walkDescendants(o, fn)
	for _, ch in ipairs(children(o)) do
		fn(ch)
		walkDescendants(ch, fn)
	end
end

local function setParent(o, p)
	local props = rawget(o, "__props")
	local old = props.Parent
	if old == p then
		return
	end
	if rawget(o, "__destroyed") then
		error("The Parent property of " .. tostring(props.Name) .. " is locked, current parent: NULL, new parent " .. tostring(p and rawget(p, "__props").Name), 3)
	end
	if rawget(o, "__service") then
		error("The Parent property of " .. tostring(props.Name) .. " is locked", 3)
	end
	if p ~= nil then
		if not isInstance(p) then
			error("Mock: Parent must be an Instance, got " .. typeof(p), 3)
		end
		local a = p
		while a do
			if a == o then
				error("Attempt to set parent of " .. tostring(props.Name) .. " to " .. tostring(rawget(p, "__props").Name) .. " would result in circular reference", 3)
			end
			a = rawget(rawget(a, "__props"), "Parent")
		end
	end
	local events = treeListeners > 0
	if events and old then
		local a = old
		while a do
			fireIf(a, "DescendantRemoving", o)
			if rawget(a, "__sig") then
				walkDescendants(o, function(d)
					fireIf(a, "DescendantRemoving", d)
				end)
			end
			a = parentOf(a)
		end
	end
	if old then
		local list = children(old)
		for i, ch in ipairs(list) do
			if ch == o then
				table.remove(list, i)
				break
			end
		end
	end
	props.Parent = p
	if p then
		table.insert(children(p), o)
	end
	for _, f in ipairs(defOf(o).onParent) do
		f(o, p, old)
	end
	if events then
		if old then
			fireIf(old, "ChildRemoved", o)
		end
		if p then
			fireIf(p, "ChildAdded", o)
			local a = p
			while a do
				if rawget(a, "__sig") and rawget(a, "__sig").DescendantAdded then
					fireIf(a, "DescendantAdded", o)
					walkDescendants(o, function(d)
						fireIf(a, "DescendantAdded", d)
					end)
				end
				a = parentOf(a)
			end
		end
		fireIf(o, "AncestryChanged", o, p)
		walkDescendants(o, function(d)
			fireIf(d, "AncestryChanged", o, p)
		end)
	end
	if rawget(o, "__sig") then
		changed(o, "Parent", p)
	end
end

---------------------------------------------------------------- Instance methods
function Inst.IsA(o, q)
	return isA(className(o), q)
end
Inst.isA = Inst.IsA
function Inst.GetChildren(o)
	return table.clone(children(o))
end
Inst.getChildren = Inst.GetChildren
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
Inst.findFirstChild = Inst.FindFirstChild
function Inst.FindFirstDescendant(o, name)
	return Inst.FindFirstChild(o, name, true)
end
function Inst.FindFirstChildOfClass(o, cls)
	for _, c in ipairs(children(o)) do
		if className(c) == cls then
			return c
		end
	end
	return nil
end
function Inst.FindFirstChildWhichIsA(o, cls, recursive)
	for _, c in ipairs(children(o)) do
		if isA(className(c), cls) then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(children(o)) do
			local f = Inst.FindFirstChildWhichIsA(c, cls, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function Inst.FindFirstAncestor(o, name)
	local a = parentOf(o)
	while a do
		if rawget(a, "__props").Name == name then
			return a
		end
		a = parentOf(a)
	end
	return nil
end
function Inst.FindFirstAncestorOfClass(o, cls)
	local a = parentOf(o)
	while a do
		if className(a) == cls then
			return a
		end
		a = parentOf(a)
	end
	return nil
end
function Inst.FindFirstAncestorWhichIsA(o, cls)
	local a = parentOf(o)
	while a do
		if isA(className(a), cls) then
			return a
		end
		a = parentOf(a)
	end
	return nil
end
function Inst.IsDescendantOf(o, anc)
	if not isInstance(anc) then
		error("Mock: IsDescendantOf expects an Instance, got " .. typeof(anc), 2)
	end
	local a = parentOf(o)
	while a do
		if a == anc then
			return true
		end
		a = parentOf(a)
	end
	return false
end
function Inst.IsAncestorOf(o, d)
	return isInstance(d) and Inst.IsDescendantOf(d, o)
end
function Inst.GetFullName(o)
	local parts = {}
	local a = o
	while a do
		if className(a) == "DataModel" then
			break
		end
		table.insert(parts, 1, tostring(rawget(a, "__props").Name))
		a = parentOf(a)
	end
	return table.concat(parts, ".")
end
function Inst.WaitForChild(o, name, timeout)
	assert(type(name) == "string", "WaitForChild expects a name")
	local c = Inst.FindFirstChild(o, name)
	if c then
		return c
	end
	if not canYield() then
		error("WaitForChild would hang: " .. name)
	end
	local start = MOCK.clock
	local warned = false
	while true do
		task.wait()
		c = Inst.FindFirstChild(o, name)
		if c then
			return c
		end
		local el = MOCK.clock - start
		if timeout and el >= timeout then
			return nil
		end
		if not timeout and el >= 5 and not warned then
			warned = true
			mockWarn('Infinite yield possible on \'' .. Inst.GetFullName(o) .. ':WaitForChild("' .. name .. '")\'')
		end
	end
end
function Inst.Destroy(o)
	if rawget(o, "__service") then
		error("Mock: cannot destroy service " .. tostring(rawget(o, "__props").Name), 2)
	end
	if rawget(o, "__destroyed") then
		return
	end
	fireIf(o, "Destroying")
	for _, c in ipairs(table.clone(children(o))) do
		Inst.Destroy(c)
	end
	if isPart(o) then
		MOCK.partCount -= 1
	end
	setParent(o, nil)
	rawset(o, "__destroyed", true)
	local sig = rawget(o, "__sig")
	if sig then
		for _, s in pairs(sig) do
			disconnectAll(s)
		end
	end
	local onDestroy = defOf(o).spec and defOf(o).spec.onDestroy
	if onDestroy then
		onDestroy(o)
	end
end
Inst.destroy = Inst.Destroy
Inst.Remove = function(o)
	o.Parent = nil
end
function Inst.ClearAllChildren(o)
	for _, c in ipairs(table.clone(children(o))) do
		Inst.Destroy(c)
	end
end
local function isArchivable(o)
	local v = rawget(o, "__props").Archivable
	return v ~= false
end
function Inst.Clone(o)
	if rawget(o, "__service") then
		error("Mock: cannot clone a service", 2)
	end
	if not isArchivable(o) then
		return nil -- like Roblox: Clone of a non-Archivable instance returns nil
	end
	local map = {}
	local list = {}
	local function copy(x)
		local c = defOf(x)
		MOCK.instanceCount += 1
		MOCK.classCounts[c.name] = (MOCK.classCounts[c.name] or 0) + 1
		local n = setmetatable({ __class = c.name, __def = c, __props = {}, __children = {}, __attrs = {} }, instMeta)
		local props = rawget(n, "__props")
		for k, v in pairs(rawget(x, "__props")) do
			if k ~= "Parent" then
				props[k] = v
			end
		end
		for k, v in pairs(rawget(x, "__attrs")) do
			rawget(n, "__attrs")[k] = v -- Clone keeps attributes (and a Model's scale)
		end
		local tags = rawget(x, "__tags")
		if tags then
			rawset(n, "__tags", table.clone(tags))
		end
		local int = rawget(x, "__int")
		if int and int.cloneable then
			rawset(n, "__int", int.clone and int.clone(int) or table.clone(int))
		end
		if c.ancestors.BasePart then
			MOCK.partCount += 1
		end
		map[x] = n
		table.insert(list, n)
		for _, ch in ipairs(children(x)) do
			if isArchivable(ch) then
				local cc = copy(ch)
				rawget(cc, "__props").Parent = n
				table.insert(children(n), cc)
			end
		end
		return n
	end
	local root = copy(o)
	-- references inside the cloned tree point at the clones (Motor6D.Part0, PrimaryPart, ...)
	for _, n in ipairs(list) do
		local props = rawget(n, "__props")
		for k, v in pairs(props) do
			if k ~= "Parent" and type(v) == "table" and getmetatable(v) == instMeta and map[v] then
				props[k] = map[v]
			end
		end
		for _, f in ipairs(defOf(n).register) do
			f(n)
		end
	end
	return root
end
Inst.clone = Inst.Clone

local ATTR_TYPES = {
	boolean = true, number = true, string = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true,
	Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true, NumberRange = true,
	Rect = true, Font = true, EnumItem = true,
}
function Inst.SetAttribute(o, k, v)
	if type(k) ~= "string" then
		error("SetAttribute: attribute name must be a string", 2)
	end
	if v ~= nil and not ATTR_TYPES[typeof(v)] then
		error("SetAttribute: " .. typeof(v) .. " is not a supported attribute type (" .. k .. ")", 2)
	end
	local attrs = rawget(o, "__attrs")
	local old = attrs[k]
	attrs[k] = v
	if old ~= v and rawget(o, "__sig") then
		fireIf(o, "AttributeChanged", k)
		fireIf(o, "attr:" .. k)
	end
end
function Inst.GetAttribute(o, k)
	return rawget(o, "__attrs")[k]
end
function Inst.GetAttributes(o)
	local out = {}
	for k, v in pairs(rawget(o, "__attrs")) do
		if string.sub(k, 1, 2) ~= "__" then
			out[k] = v
		end
	end
	return out
end
function Inst.GetAttributeChangedSignal(o, k)
	return getSignal(o, "attr:" .. k)
end
function Inst.GetPropertyChangedSignal(o, k)
	local c = defOf(o)
	if c.props[k] == nil and not c.ro[k] and not c.get[k] and not c.permissive then
		error(tostring(k) .. " is not a valid property name.", 2)
	end
	return getSignal(o, "prop:" .. k)
end
local tagged = {} -- [tag] = { [inst] = true }
function Inst.AddTag(o, tag)
	local tags = rawget(o, "__tags")
	if not tags then
		tags = {}
		rawset(o, "__tags", tags)
	end
	tags[tag] = true
	tagged[tag] = tagged[tag] or {}
	tagged[tag][o] = true
end
function Inst.RemoveTag(o, tag)
	local tags = rawget(o, "__tags")
	if tags then
		tags[tag] = nil
	end
	if tagged[tag] then
		tagged[tag][o] = nil
	end
end
function Inst.HasTag(o, tag)
	local tags = rawget(o, "__tags")
	return tags ~= nil and tags[tag] == true
end
function Inst.GetTags(o)
	local out = {}
	for t in pairs(rawget(o, "__tags") or {}) do
		table.insert(out, t)
	end
	table.sort(out)
	return out
end
function Inst.GetDebugId(o)
	return tostring(o)
end

local function eachPart(o, fn)
	for _, d in ipairs(Inst.GetDescendants(o)) do
		if isPart(d) then
			fn(d)
		end
	end
end
MOCK.eachPart = eachPart

local PV = {}
function PV.GetPivot(o)
	if defOf(o).ancestors.Model then
		local pp = rawget(o, "__props").PrimaryPart
		if pp then
			return pp.CFrame
		end
		return o.WorldPivot
	end
	return o.CFrame
end
function PV.PivotTo(o, cf)
	assert(MOCK.isCF(cf), "PivotTo expects a CFrame")
	if defOf(o).ancestors.Model then
		local old = PV.GetPivot(o)
		local delta = cf * old:Inverse()
		eachPart(o, function(p)
			p.CFrame = delta * p.CFrame
		end)
		rawget(o, "__props").WorldPivot = cf
	else
		o.CFrame = cf
	end
end

---------------------------------------------------------------- Class definitions
-- "Name:type Name2:type2" -> { Name = "type", ... }
local function P(s)
	local t = {}
	for word in string.gmatch(s, "%S+") do
		local name, ty = string.match(word, "^([^:]+):(.+)$")
		if name then
			t[name] = ty
		else
			t[word] = "any"
		end
	end
	return t
end
local function merge(a, b)
	local t = table.clone(a)
	for k, v in pairs(b) do
		t[k] = v
	end
	return t
end
-- properties only Studio (plugins / the command bar / edit mode) may write
local function editOnly(o, v, k)
	if curCtx ~= "edit" then
		error("Mock: " .. rawget(o, "__class") .. "." .. k .. " can't be set by game scripts (lacking capability)", 3)
	end
	store(o, k, v)
end
MOCK.editOnly = editOnly
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function parentPartCF(att)
	local p = parentOf(att)
	if p and isPart(p) then
		return p.CFrame
	end
	return CFrame.identity
end
local function deg(r)
	return r * 180 / math.pi
end
local function rad(d)
	return d * math.pi / 180
end
local function orientationOf(cf)
	local x, y, z = cf:ToOrientation()
	return Vector3.new(deg(x), deg(y), deg(z))
end
local function fromOrientationDeg(v)
	return CFrame.fromOrientation(rad(v.X), rad(v.Y), rad(v.Z))
end

def("Instance", {
	abstract = true,
	props = P("Name:string Archivable:boolean Parent:Instance"),
	ro = { ClassName = true },
	get = {
		ClassName = function(o)
			return className(o)
		end,
	},
	set = {
		Parent = function(o, v)
			setParent(o, v)
		end,
	},
	defaults = { Archivable = true },
	methods = Inst,
	events = "Changed Destroying AncestryChanged ChildAdded ChildRemoved DescendantAdded DescendantRemoving AttributeChanged",
})
def("PVInstance", { base = "Instance", abstract = true, methods = PV })

---------------------------------------------------------------- Parts
local PART_PROPS = P(
	"Anchored:boolean CanCollide:boolean CanTouch:boolean CanQuery:boolean CastShadow:boolean Size:Vector3 CFrame:CFrame "
		.. "Position:Vector3 Orientation:Vector3 Rotation:Vector3 Color:Color3 BrickColor Material:Enum:Material Transparency:number "
		.. "Reflectance:number Shape:Enum:PartType TopSurface:Enum:SurfaceType BottomSurface:Enum:SurfaceType "
		.. "LeftSurface:Enum:SurfaceType RightSurface:Enum:SurfaceType FrontSurface:Enum:SurfaceType "
		.. "BackSurface:Enum:SurfaceType Locked:boolean Massless:boolean MaterialVariant:string "
		.. "LocalTransparencyModifier:number AssemblyLinearVelocity:Vector3 AssemblyAngularVelocity:Vector3 "
		.. "CustomPhysicalProperties CollisionGroup:string RootPriority:int Velocity:Vector3 EnableFluidForces:boolean "
		.. "PivotOffset:CFrame AudioCanCollide:boolean"
)
local function partSetSize(o, v)
	if v.X > 2048 or v.Y > 2048 or v.Z > 2048 then
		mockWarn("part larger than 2048 studs on an axis (" .. tostring(rawget(o, "__props").Name) .. ")")
	end
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then
		error("Part.Size is NaN", 3)
	end
	if v.X < 0 or v.Y < 0 or v.Z < 0 then
		error("Part.Size must be positive, got " .. tostring(v), 3)
	end
	if v.X < 0.001 or v.Y < 0.001 or v.Z < 0.001 then
		v = v:Max(Vector3.new(0.001, 0.001, 0.001)) -- Roblox clamps tiny sizes
	end
	store(o, "Size", v)
end
local function partSetCFrame(o, v)
	local props = rawget(o, "__props")
	props.Position = v.Position
	store(o, "CFrame", v)
end
local function partSetPosition(o, v)
	local props = rawget(o, "__props")
	props.Position = v
	store(o, "CFrame", CFrame.new(v) * props.CFrame.Rotation)
end
local function partSetOrientation(o, v)
	local props = rawget(o, "__props")
	store(o, "CFrame", CFrame.new(props.CFrame.Position) * fromOrientationDeg(v))
end
local function jointsOf(part)
	local out = {}
	for _, j in ipairs(MOCK._joints) do
		if not rawget(j, "__destroyed") then
			local pr = rawget(j, "__props")
			if pr.Part0 == part or pr.Part1 == part then
				table.insert(out, j)
			end
		end
	end
	return out
end
def("BasePart", {
	base = "PVInstance",
	abstract = true,
	props = PART_PROPS,
	ro = { AssemblyRootPart = true, AssemblyMass = true, Mass = true, ResizeIncrement = true, ExtentsSize = true },
	defaults = {
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
		CastShadow = true,
		Color = Color3.new(163 / 255, 162 / 255, 165 / 255),
		Reflectance = 0,
		LocalTransparencyModifier = 0,
		Massless = false,
		Locked = false,
		AssemblyLinearVelocity = Vector3.zero,
		AssemblyAngularVelocity = Vector3.zero,
		Velocity = Vector3.zero,
		CollisionGroup = "Default",
		RootPriority = 0,
		MaterialVariant = "",
		PivotOffset = CFrame.identity,
		EnableFluidForces = true,
		AudioCanCollide = true,
		ResizeIncrement = 1,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		LeftSurface = Enum.SurfaceType.Smooth,
		RightSurface = Enum.SurfaceType.Smooth,
		FrontSurface = Enum.SurfaceType.Smooth,
		BackSurface = Enum.SurfaceType.Smooth,
	},
	get = {
		Orientation = function(o)
			return orientationOf(o.CFrame)
		end,
		Rotation = function(o)
			local x, y, z = o.CFrame:ToEulerAnglesXYZ()
			return Vector3.new(deg(x), deg(y), deg(z))
		end,
		AssemblyRootPart = function(o)
			return o
		end,
		Mass = function(o)
			local s = o.Size
			return s.X * s.Y * s.Z * 0.7
		end,
		AssemblyMass = function(o)
			local s = o.Size
			return s.X * s.Y * s.Z * 0.7
		end,
		ExtentsSize = function(o)
			return o.Size
		end,
	},
	set = {
		Size = partSetSize,
		CFrame = partSetCFrame,
		Position = partSetPosition,
		Orientation = partSetOrientation,
		Rotation = function(o, v)
			local props = rawget(o, "__props")
			store(o, "CFrame", CFrame.new(props.CFrame.Position) * CFrame.Angles(rad(v.X), rad(v.Y), rad(v.Z)))
		end,
	},
	init = function(o)
		MOCK.partCount += 1
		local p = rawget(o, "__props")
		p.Size = Vector3.new(4, 1, 2)
		p.CFrame = CFrame.new()
		p.Position = Vector3.new()
		p.Anchored = false
		p.Transparency = 0
		p.Material = Enum.Material.Plastic
	end,
	methods = {
		GetMass = function(o)
			return o.Mass
		end,
		GetJoints = jointsOf,
		GetConnectedParts = function(o)
			local out = {}
			for _, j in ipairs(jointsOf(o)) do
				local pr = rawget(j, "__props")
				table.insert(out, pr.Part0 == o and pr.Part1 or pr.Part0)
			end
			return out
		end,
		BreakJoints = function(o)
			for _, j in ipairs(jointsOf(o)) do
				j:Destroy()
			end
		end,
		GetTouchingParts = function()
			return {}
		end,
		ApplyImpulse = function(o, v)
			assert(isV3(v), "ApplyImpulse expects a Vector3")
		end,
		ApplyAngularImpulse = function(o, v)
			assert(isV3(v), "ApplyAngularImpulse expects a Vector3")
		end,
		GetRootPart = function(o)
			return o
		end,
		IsGrounded = function(o)
			return o.Anchored
		end,
		GetVelocityAtPosition = function()
			return Vector3.zero
		end,
		SetNetworkOwner = function(o, player)
			if curCtx == "client" then
				error("SetNetworkOwner can only be called from the server", 2)
			end
			if o.Anchored then
				error("Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts.", 2)
			end
		end,
		SetNetworkOwnershipAuto = function() end,
		GetNetworkOwner = function()
			return nil
		end,
		CanSetNetworkOwnership = function(o)
			return not o.Anchored
		end,
	},
	events = "Touched TouchEnded",
})
def("FormFactorPart", { base = "BasePart", abstract = true })
def("TriangleMeshPart", { base = "BasePart", abstract = true })
def("Part", { base = "FormFactorPart", defaults = { Shape = Enum.PartType.Block } })
def("WedgePart", { base = "FormFactorPart" })
def("CornerWedgePart", { base = "BasePart" })
def("TrussPart", { base = "BasePart", props = P("Style") })
def("MeshPart", {
	base = "TriangleMeshPart",
	props = P("CollisionFidelity:Enum:CollisionFidelity MeshId:string TextureID:string DoubleSided:boolean RenderFidelity:Enum:RenderFidelity"),
	ro = { MeshSize = true },
	defaults = { MeshId = "", TextureID = "", DoubleSided = false },
	get = {
		MeshSize = function(o)
			return o.Size
		end,
	},
})
def("SpawnLocation", {
	base = "Part",
	props = P("Neutral:boolean Duration:number Enabled:boolean AllowTeamChangeOnTouch:boolean TeamColor"),
	defaults = { Neutral = true, Duration = 10, Enabled = true, AllowTeamChangeOnTouch = false },
})

---------------------------------------------------------------- Models
local function boundingBox(o)
	local pivot = PV.GetPivot(o)
	local rot = pivot.Rotation
	local inv = rot:Inverse()
	local lo, hi
	eachPart(o, function(p)
		local cf, s = p.CFrame, p.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local w = inv * (cf * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz))
					lo = lo and lo:Min(w) or w
					hi = hi and hi:Max(w) or w
				end
			end
		end
	end)
	if not lo then
		return pivot, Vector3.zero
	end
	return rot + rot * ((lo + hi) / 2), hi - lo
end
def("Model", {
	base = "PVInstance",
	props = P("WorldPivot:CFrame PrimaryPart:Instance:BasePart ModelStreamingMode:Enum:ModelStreamingMode LevelOfDetail:Enum:ModelLevelOfDetail"),
	defaults = { WorldPivot = CFrame.identity },
	methods = {
		GetBoundingBox = boundingBox,
		GetExtentsSize = function(o)
			local _, s = boundingBox(o)
			return s
		end,
		MoveTo = function(o, pos)
			assert(isV3(pos), "MoveTo expects a Vector3")
			local pv = PV.GetPivot(o)
			PV.PivotTo(o, pv + (pos - pv.Position))
		end,
		TranslateBy = function(o, d)
			assert(isV3(d), "TranslateBy expects a Vector3")
			PV.PivotTo(o, PV.GetPivot(o) + d)
		end,
		SetPrimaryPartCFrame = function(o, cf)
			assert(rawget(o, "__props").PrimaryPart, "Model:SetPrimaryPartCFrame() failed because no PrimaryPart has been set")
			PV.PivotTo(o, cf)
		end,
		GetPrimaryPartCFrame = function(o)
			local pp = rawget(o, "__props").PrimaryPart
			return pp and pp.CFrame or nil
		end,
		ScaleTo = function(o, s)
			assert(type(s) == "number" and s > 0, "ScaleTo expects a positive number")
			local cur = rawget(o, "__attrs").__scale or 1
			local f = s / cur
			local pivot = PV.GetPivot(o)
			eachPart(o, function(p)
				local rel = pivot:Inverse() * p.CFrame
				local pos = rel.Position * f
				p.CFrame = pivot * (CFrame.new(pos) * rel.Rotation)
				p.Size = p.Size * f
			end)
			rawget(o, "__attrs").__scale = s
		end,
		GetScale = function(o)
			return rawget(o, "__attrs").__scale or 1
		end,
		BreakJoints = function(o)
			for _, d in ipairs(Inst.GetDescendants(o)) do
				if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
					d:Destroy()
				end
			end
		end,
	},
})
def("WorldRoot", { base = "Model", abstract = true })
def("WorldModel", { base = "WorldRoot" })
def("Folder", { base = "Instance" })
def("Configuration", { base = "Instance" })

---------------------------------------------------------------- Scripts and values
local function setEnabled(o, on)
	local props = rawget(o, "__props")
	local was = props.Enabled ~= false
	props.Disabled = not on
	store(o, "Enabled", on)
	if on and not was then
		local int = rawget(o, "__int")
		if int and int.onEnable then
			int.onEnable(o)
		end
	end
end
def("LuaSourceContainer", { base = "Instance", abstract = true, props = P("Source:string"), defaults = { Source = "" } })
def("BaseScript", {
	base = "LuaSourceContainer",
	abstract = true,
	props = P("Disabled:boolean Enabled:boolean RunContext:Enum:RunContext LinkedSource:string"),
	defaults = { Disabled = false, Enabled = true, RunContext = Enum.RunContext.Legacy },
	set = {
		Enabled = function(o, v)
			setEnabled(o, v)
		end,
		Disabled = function(o, v)
			setEnabled(o, not v)
		end,
	},
})
def("Script", { base = "BaseScript" })
def("LocalScript", { base = "Script" })
def("ModuleScript", { base = "LuaSourceContainer" })
def("ValueBase", { base = "Instance", abstract = true })
def("StringValue", { base = "ValueBase", props = P("Value:string"), defaults = { Value = "" } })
def("NumberValue", { base = "ValueBase", props = P("Value:number"), defaults = { Value = 0 } })
def("IntValue", { base = "ValueBase", props = P("Value:int"), defaults = { Value = 0 } })
def("BoolValue", { base = "ValueBase", props = P("Value:boolean"), defaults = { Value = false } })
def("ObjectValue", { base = "ValueBase", props = P("Value:Instance") })
def("Color3Value", { base = "ValueBase", props = P("Value:Color3"), defaults = { Value = BLACK } })
def("Vector3Value", { base = "ValueBase", props = P("Value:Vector3"), defaults = { Value = Vector3.zero } })
def("CFrameValue", { base = "ValueBase", props = P("Value:CFrame"), defaults = { Value = CFrame.identity } })

---------------------------------------------------------------- Lights, effects, decoration
def("Light", {
	base = "Instance",
	abstract = true,
	props = P("Brightness:number Color:Color3 Enabled:boolean Shadows:boolean"),
	defaults = { Brightness = 1, Color = WHITE, Enabled = true, Shadows = false },
})
local function lightRange(o, v)
	if v > 60 then
		mockWarn("light Range above 60 is clamped by Roblox")
	end
	store(o, "Range", v)
end
def("PointLight", { base = "Light", props = P("Range:number"), defaults = { Range = 8 }, set = { Range = lightRange } })
def("SpotLight", {
	base = "Light",
	props = P("Range:number Angle:number Face:Enum:NormalId"),
	defaults = { Range = 16, Angle = 90, Face = Enum.NormalId.Front },
	set = { Range = lightRange },
})
def("SurfaceLight", {
	base = "Light",
	props = P("Range:number Angle:number Face:Enum:NormalId"),
	defaults = { Range = 16, Angle = 90, Face = Enum.NormalId.Front },
	set = { Range = lightRange },
})

local function attWorld(o)
	return parentPartCF(o) * o.CFrame
end
def("Attachment", {
	base = "Instance",
	props = P(
		"Position:Vector3 CFrame:CFrame Orientation:Vector3 Axis:Vector3 SecondaryAxis:Vector3 Visible:boolean "
			.. "WorldPosition:Vector3 WorldCFrame:CFrame WorldOrientation:Vector3 WorldAxis:Vector3 WorldSecondaryAxis:Vector3"
	),
	defaults = { Position = Vector3.zero, CFrame = CFrame.identity, Visible = false },
	get = {
		Orientation = function(o)
			return orientationOf(o.CFrame)
		end,
		Axis = function(o)
			return o.CFrame.RightVector
		end,
		SecondaryAxis = function(o)
			return o.CFrame.UpVector
		end,
		WorldCFrame = attWorld,
		WorldPosition = function(o)
			return attWorld(o).Position
		end,
		WorldOrientation = function(o)
			return orientationOf(attWorld(o))
		end,
		WorldAxis = function(o)
			return attWorld(o).RightVector
		end,
		WorldSecondaryAxis = function(o)
			return attWorld(o).UpVector
		end,
	},
	set = {
		Position = function(o, v)
			rawget(o, "__props").Position = v
			store(o, "CFrame", CFrame.new(v) * o.CFrame.Rotation)
		end,
		CFrame = function(o, v)
			rawget(o, "__props").Position = v.Position
			store(o, "CFrame", v)
		end,
		Orientation = function(o, v)
			o.CFrame = CFrame.new(o.Position) * fromOrientationDeg(v)
		end,
		Axis = function(o, v)
			o.CFrame = CFrame.fromMatrix(o.Position, v.Unit, o.CFrame.UpVector)
		end,
		SecondaryAxis = function(o, v)
			o.CFrame = CFrame.fromMatrix(o.Position, o.CFrame.RightVector, v.Unit)
		end,
		WorldCFrame = function(o, v)
			o.CFrame = parentPartCF(o):Inverse() * v
		end,
		WorldPosition = function(o, v)
			o.Position = parentPartCF(o):Inverse() * v
		end,
		WorldOrientation = function(o, v)
			o.CFrame = parentPartCF(o):Inverse() * (CFrame.new(attWorld(o).Position) * fromOrientationDeg(v))
		end,
		WorldAxis = function(o, v)
			local w = attWorld(o)
			o.CFrame = parentPartCF(o):Inverse() * CFrame.fromMatrix(w.Position, v.Unit, w.UpVector)
		end,
		WorldSecondaryAxis = function(o, v)
			local w = attWorld(o)
			o.CFrame = parentPartCF(o):Inverse() * CFrame.fromMatrix(w.Position, w.RightVector, v.Unit)
		end,
	},
})

def("ParticleEmitter", {
	base = "Instance",
	props = P(
		"Texture:string Color:ColorSequence Size:NumberSequence Transparency:NumberSequence Lifetime:NumberRange Rate:number "
			.. "Speed:NumberRange SpreadAngle:Vector2 Acceleration:Vector3 Drag:number LightEmission:number LightInfluence:number "
			.. "Rotation:NumberRange RotSpeed:NumberRange EmissionDirection:Enum:NormalId Shape:Enum:ParticleEmitterShape "
			.. "ShapeStyle:Enum:ParticleEmitterShapeStyle ShapeInOut:Enum:ParticleEmitterShapeInOut ShapePartial:number "
			.. "Enabled:boolean LockedToPart:boolean ZOffset:number Orientation:Enum:ParticleOrientation VelocityInheritance:number "
			.. "Brightness:number TimeScale:number Squash:NumberSequence WindAffectsDrag:boolean FlipbookFramerate:NumberRange "
			.. "FlipbookLayout:Enum:ParticleFlipbookLayout FlipbookMode:Enum:ParticleFlipbookMode FlipbookStartRandom:boolean "
			.. "VelocitySpread:number"
	),
	defaults = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(WHITE),
		Size = NumberSequence.new(1),
		Transparency = NumberSequence.new(0),
		Lifetime = NumberRange.new(5, 10),
		Rate = 5,
		Speed = NumberRange.new(5),
		SpreadAngle = Vector2.zero,
		Acceleration = Vector3.zero,
		Drag = 0,
		LightEmission = 0,
		LightInfluence = 1,
		Rotation = NumberRange.new(0),
		RotSpeed = NumberRange.new(0),
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		ShapePartial = 1,
		Enabled = true,
		LockedToPart = false,
		ZOffset = 0,
		Orientation = Enum.ParticleOrientation.FacingCamera,
		VelocityInheritance = 0,
		Brightness = 1,
		TimeScale = 1,
		Squash = NumberSequence.new(0),
		WindAffectsDrag = false,
		FlipbookFramerate = NumberRange.new(1),
		FlipbookLayout = Enum.ParticleFlipbookLayout.None,
		FlipbookMode = Enum.ParticleFlipbookMode.Loop,
		FlipbookStartRandom = false,
	},
	methods = {
		Emit = function(o, n)
			n = n or 16
			assert(type(n) == "number", "ParticleEmitter:Emit expects a number")
			MOCK.particlesEmitted += n
		end,
		Clear = function() end,
	},
})
def("Fire", { base = "Instance", props = { "Size", "Heat", "Color", "SecondaryColor", "Enabled", "TimeScale" } })
def("Smoke", { base = "Instance", props = { "Color", "Opacity", "RiseVelocity", "Size", "Enabled", "TimeScale" } })
def("Sparkles", { base = "Instance", props = { "SparkleColor", "Enabled", "TimeScale" } })
def("Beam", {
	base = "Instance",
	props = P(
		"Attachment0:Instance:Attachment Attachment1:Instance:Attachment Color:ColorSequence Transparency:NumberSequence "
			.. "Width0:number Width1:number LightEmission:number LightInfluence:number FaceCamera:boolean Segments:int "
			.. "Texture:string TextureSpeed:number TextureLength:number TextureMode:Enum:TextureMode CurveSize0:number "
			.. "CurveSize1:number Brightness:number Enabled:boolean ZOffset:number"
	),
	defaults = {
		Color = ColorSequence.new(WHITE),
		Transparency = NumberSequence.new(0.5),
		Width0 = 1,
		Width1 = 1,
		LightEmission = 0,
		LightInfluence = 0,
		FaceCamera = false,
		Segments = 10,
		Texture = "",
		TextureSpeed = 1,
		TextureLength = 1,
		TextureMode = Enum.TextureMode.Stretch,
		CurveSize0 = 0,
		CurveSize1 = 0,
		Brightness = 1,
		Enabled = true,
		ZOffset = 0,
	},
	set = {
		Segments = function(o, v)
			if v < 1 or v > 1000 then
				mockWarn("Beam.Segments outside 1..1000 is clamped")
			end
			store(o, "Segments", v)
		end,
	},
	methods = { SetTextureOffset = function() end },
})
def("Trail", {
	base = "Instance",
	props = P(
		"Attachment0:Instance:Attachment Attachment1:Instance:Attachment Color:ColorSequence Transparency:NumberSequence "
			.. "Lifetime:number MinLength:number MaxLength:number WidthScale:NumberSequence LightEmission:number "
			.. "LightInfluence:number Brightness:number FaceCamera:boolean Texture:string TextureLength:number "
			.. "TextureMode:Enum:TextureMode Enabled:boolean"
	),
	defaults = {
		Color = ColorSequence.new(WHITE),
		Transparency = NumberSequence.new(0.5),
		Lifetime = 2,
		MinLength = 0.1,
		MaxLength = 0,
		WidthScale = NumberSequence.new(1),
		LightEmission = 0,
		LightInfluence = 1,
		Brightness = 1,
		FaceCamera = false,
		Texture = "",
		TextureLength = 1,
		TextureMode = Enum.TextureMode.Stretch,
		Enabled = true,
	},
	set = {
		Lifetime = function(o, v)
			if v < 0 or v > 20 then
				mockWarn("Trail.Lifetime outside 0..20 is clamped")
			end
			store(o, "Lifetime", v)
		end,
	},
	methods = { Clear = function() end },
})
MOCK._highlights = {}
def("Highlight", {
	base = "Instance",
	props = P(
		"Adornee:Instance DepthMode:Enum:HighlightDepthMode Enabled:boolean FillColor:Color3 FillTransparency:number "
			.. "OutlineColor:Color3 OutlineTransparency:number"
	),
	defaults = {
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Enabled = true,
		FillColor = Color3.new(1, 0, 0),
		FillTransparency = 0.5,
		OutlineColor = WHITE,
		OutlineTransparency = 0,
	},
	register = function(o)
		table.insert(MOCK._highlights, o)
	end,
})
def("DataModelMesh", {
	base = "Instance",
	abstract = true,
	props = P("Scale:Vector3 Offset:Vector3 VertexColor:Vector3"),
	defaults = { Scale = Vector3.one, Offset = Vector3.zero, VertexColor = Vector3.one },
})
def("FileMesh", { base = "DataModelMesh", props = P("MeshId:string TextureId:string"), defaults = { MeshId = "", TextureId = "" } })
def("SpecialMesh", { base = "FileMesh", props = P("MeshType:Enum:MeshType"), defaults = { MeshType = Enum.MeshType.Head } })
def("BevelMesh", { base = "DataModelMesh", abstract = true })
def("BlockMesh", { base = "BevelMesh" })
def("CylinderMesh", { base = "BevelMesh" })
def("SurfaceAppearance", {
	base = "Instance",
	props = P("AlphaMode:Enum:AlphaMode Color:Color3 ColorMap:string MetalnessMap:string NormalMap:string RoughnessMap:string"),
	defaults = { AlphaMode = Enum.AlphaMode.Overlay, Color = WHITE, ColorMap = "", MetalnessMap = "", NormalMap = "", RoughnessMap = "" },
	set = { ColorMap = editOnly, MetalnessMap = editOnly, NormalMap = editOnly, RoughnessMap = editOnly },
})
def("FaceInstance", { base = "Instance", abstract = true, props = P("Face:Enum:NormalId"), defaults = { Face = Enum.NormalId.Front } })
def("Decal", {
	base = "FaceInstance",
	props = P("Texture:string Color3:Color3 Transparency:number ZIndex:int LocalTransparencyModifier:number"),
	defaults = { Texture = "", Color3 = WHITE, Transparency = 0, ZIndex = 1, LocalTransparencyModifier = 0 },
})
def("Texture", {
	base = "Decal",
	props = P("StudsPerTileU:number StudsPerTileV:number OffsetStudsU:number OffsetStudsV:number"),
	defaults = { StudsPerTileU = 2, StudsPerTileV = 2, OffsetStudsU = 0, OffsetStudsV = 0 },
})

---------------------------------------------------------------- Lighting and post effects
def("PostEffect", { base = "Instance", abstract = true, props = P("Enabled:boolean"), defaults = { Enabled = true } })
def("BloomEffect", { base = "PostEffect", props = P("Intensity:number Size:number Threshold:number"), defaults = { Intensity = 1, Size = 24, Threshold = 2 } })
def("BlurEffect", { base = "PostEffect", props = P("Size:number"), defaults = { Size = 24 } })
def("ColorCorrectionEffect", {
	base = "PostEffect",
	props = P("Brightness:number Contrast:number Saturation:number TintColor:Color3"),
	defaults = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE },
})
def("DepthOfFieldEffect", {
	base = "PostEffect",
	props = P("FarIntensity:number FocusDistance:number InFocusRadius:number NearIntensity:number"),
	defaults = { FarIntensity = 0.75, FocusDistance = 0.05, InFocusRadius = 30, NearIntensity = 0.75 },
})
def("SunRaysEffect", { base = "PostEffect", props = P("Intensity:number Spread:number"), defaults = { Intensity = 0.25, Spread = 1 } })
def("Atmosphere", {
	base = "Instance",
	props = P("Density:number Offset:number Color:Color3 Decay:Color3 Glare:number Haze:number"),
	defaults = { Density = 0.395, Offset = 0, Color = rgb(199, 199, 199), Decay = rgb(106, 112, 125), Glare = 0, Haze = 0 },
})
def("Sky", {
	base = "Instance",
	props = P(
		"SkyboxBk:string SkyboxDn:string SkyboxFt:string SkyboxLf:string SkyboxRt:string SkyboxUp:string "
			.. "CelestialBodiesShown:boolean MoonAngularSize:number MoonTextureId:string StarCount:int SunAngularSize:number "
			.. "SunTextureId:string SkyboxOrientation:Vector3"
	),
	defaults = {
		SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex",
		SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex",
		SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex",
		SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex",
		SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex",
		SkyboxUp = "rbxasset://textures/sky/sky512_up.tex",
		CelestialBodiesShown = true,
		MoonAngularSize = 11,
		MoonTextureId = "rbxasset://sky/moon.jpg",
		StarCount = 3000,
		SunAngularSize = 21,
		SunTextureId = "rbxasset://sky/sun.jpg",
		SkyboxOrientation = Vector3.zero,
	},
})
def("Clouds", { base = "Instance", props = P("Cover:number Density:number Color:Color3 Enabled:boolean"), defaults = { Cover = 0.5, Density = 0.7, Color = WHITE, Enabled = true } })

local function clockToString(h)
	h = h % 24
	local s = math.floor(h * 3600 + 0.5)
	return string.format("%02d:%02d:%02d", math.floor(s / 3600) % 24, math.floor(s / 60) % 60, s % 60)
end
local function sunDir(clock, latDeg, offset)
	-- Approximate: equinox sun, hour angle from ClockTime, east = +X, north = -Z.
	local h = ((clock - 12) / 24) * 2 * math.pi + (offset or 0)
	local lat = rad(latDeg)
	local east = -math.sin(h)
	local up = math.cos(lat) * math.cos(h)
	local north = -math.sin(lat) * math.cos(h)
	return Vector3.new(east, up, -north).Unit
end
def("Lighting", {
	base = "Instance",
	service = true,
	props = P(
		"Ambient:Color3 Brightness:number ColorShift_Bottom:Color3 ColorShift_Top:Color3 EnvironmentDiffuseScale:number "
			.. "EnvironmentSpecularScale:number GlobalShadows:boolean OutdoorAmbient:Color3 ShadowSoftness:number ClockTime:number "
			.. "GeographicLatitude:number TimeOfDay:string ExposureCompensation:number FogColor:Color3 FogEnd:number FogStart:number "
			.. "Technology:Enum:Technology LightingStyle:Enum:LightingStyle PrioritizeLightingQuality:boolean ShadowColor:Color3 Outlines:boolean"
	),
	defaults = {
		Ambient = rgb(70, 70, 70),
		Brightness = 2,
		ColorShift_Bottom = BLACK,
		ColorShift_Top = BLACK,
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		GlobalShadows = true,
		OutdoorAmbient = rgb(70, 70, 70),
		ShadowSoftness = 0.2,
		ClockTime = 14.5,
		GeographicLatitude = 41.733,
		ExposureCompensation = 0,
		FogColor = rgb(192, 192, 192),
		FogEnd = 100000,
		FogStart = 0,
		Technology = Enum.Technology.ShadowMap,
		LightingStyle = Enum.LightingStyle.Realistic,
		PrioritizeLightingQuality = true,
		ShadowColor = rgb(178, 178, 183),
		Outlines = false,
	},
	get = {
		TimeOfDay = function(o)
			return clockToString(o.ClockTime)
		end,
	},
	set = {
		Technology = editOnly,
		ClockTime = function(o, v)
			store(o, "ClockTime", v % 24)
		end,
		TimeOfDay = function(o, v)
			local h, m, s = string.match(v, "^(%d+):?(%d*):?(%d*)$")
			assert(h, "Lighting.TimeOfDay: bad time string " .. v)
			o.ClockTime = tonumber(h) + (tonumber(m) or 0) / 60 + (tonumber(s) or 0) / 3600
		end,
	},
	methods = {
		GetSunDirection = function(o)
			return sunDir(o.ClockTime, o.GeographicLatitude)
		end,
		GetMoonDirection = function(o)
			return sunDir(o.ClockTime, o.GeographicLatitude, math.pi)
		end,
		GetMinutesAfterMidnight = function(o)
			return o.ClockTime * 60
		end,
		SetMinutesAfterMidnight = function(o, m)
			assert(type(m) == "number", "SetMinutesAfterMidnight expects a number")
			o.ClockTime = m / 60
		end,
		GetMoonPhase = function()
			return 0.75
		end,
	},
	events = "LightingChanged",
})

---------------------------------------------------------------- Sound
MOCK._sounds = {}
local function soundLength(o)
	local id = rawget(o, "__props").SoundId or ""
	if id == "" then
		return 0
	end
	return MOCK.soundLengths and MOCK.soundLengths[id] or 2
end
local function soundPlay(o)
	local int = internal(o)
	local props = rawget(o, "__props")
	MOCK.soundLog[#MOCK.soundLog + 1] = { id = props.SoundId or "", t = MOCK.clock, name = props.Name }
	if not int.playing then
		int.playing = true
		int.paused = false
		props.Playing = true
		table.insert(MOCK._sounds, o)
		fireIf(o, "Played", props.SoundId or "")
	end
end
local function soundStop(o, reset)
	local int = internal(o)
	local props = rawget(o, "__props")
	if int.playing then
		int.playing = false
		props.Playing = false
		for i, s in ipairs(MOCK._sounds) do
			if s == o then
				table.remove(MOCK._sounds, i)
				break
			end
		end
	end
	if reset then
		props.TimePosition = 0
	end
end
def("Sound", {
	base = "Instance",
	props = P(
		"SoundId:string Volume:number PlaybackSpeed:number Looped:boolean Playing:boolean TimePosition:number "
			.. "RollOffMode:Enum:RollOffMode RollOffMinDistance:number RollOffMaxDistance:number PlayOnRemove:boolean "
			.. "SoundGroup:Instance:SoundGroup EmitterSize:number Pitch:number"
	),
	ro = { TimeLength = true, IsPlaying = true, IsLoaded = true, IsPaused = true },
	defaults = {
		SoundId = "",
		Volume = 0.5,
		PlaybackSpeed = 1,
		Looped = false,
		Playing = false,
		TimePosition = 0,
		RollOffMode = Enum.RollOffMode.Inverse,
		RollOffMinDistance = 10,
		RollOffMaxDistance = 10000,
		PlayOnRemove = false,
	},
	get = {
		TimeLength = soundLength,
		IsPlaying = function(o)
			return internal(o).playing == true
		end,
		IsPaused = function(o)
			return not internal(o).playing
		end,
		IsLoaded = function(o)
			return (rawget(o, "__props").SoundId or "") ~= ""
		end,
	},
	set = {
		Playing = function(o, v)
			if v then
				soundPlay(o)
			else
				soundStop(o, false)
			end
		end,
		Volume = function(o, v)
			if v < 0 or v > 10 then
				mockWarn("Sound.Volume outside 0..10 is clamped")
			end
			store(o, "Volume", v)
		end,
	},
	methods = {
		Play = function(o)
			rawget(o, "__props").TimePosition = rawget(o, "__props").TimePosition or 0
			soundPlay(o)
		end,
		Stop = function(o)
			soundStop(o, true)
			fireIf(o, "Stopped", rawget(o, "__props").SoundId or "")
		end,
		Pause = function(o)
			soundStop(o, false)
			fireIf(o, "Paused", rawget(o, "__props").SoundId or "")
		end,
		Resume = function(o)
			soundPlay(o)
			fireIf(o, "Resumed", rawget(o, "__props").SoundId or "")
		end,
	},
	events = "Played Paused Resumed Stopped Ended Loaded DidLoop",
	onDestroy = function(o)
		soundStop(o, false)
	end,
})
def("SoundGroup", { base = "Instance", props = P("Volume:number"), defaults = { Volume = 0.5 } })

---------------------------------------------------------------- Events and functions
local function copyArgs(...)
	local args = table.pack(...)
	for i = 1, args.n do
		local v = args[i]
		if type(v) == "table" and getmetatable(v) == nil then
			args[i] = table.clone(v)
		elseif type(v) == "function" then
			args[i] = nil -- functions don't replicate
		end
	end
	return args
end
MOCK._remoteQueue = {}
local function remoteQueue(remote, dir, player, args)
	if not Inst.IsDescendantOf(remote, game) then
		mockWarn("RemoteEvent " .. tostring(rawget(remote, "__props").Name) .. " fired while not in the DataModel (nothing receives it)")
		return
	end
	table.insert(MOCK.remoteLog, { remote = remote, dir = dir, player = player, args = args, t = MOCK.clock })
	table.insert(MOCK._remoteQueue, { remote = remote, dir = dir, player = player, args = args })
end
local remoteMethods = {
	FireServer = function(o, ...)
		if curCtx == "server" then
			error("FireServer can only be called from the client", 2)
		end
		remoteQueue(o, "server", MOCK.localPlayer, copyArgs(...))
	end,
	FireClient = function(o, player, ...)
		if curCtx == "client" then
			error("FireClient can only be called from the server", 2)
		end
		if not (isInstance(player) and player:IsA("Player")) then
			error("FireClient: player argument must be a Player", 2)
		end
		remoteQueue(o, "client", player, copyArgs(...))
	end,
	FireAllClients = function(o, ...)
		if curCtx == "client" then
			error("FireAllClients can only be called from the server", 2)
		end
		remoteQueue(o, "client", nil, copyArgs(...))
	end,
}
def("BaseRemoteEvent", {
	base = "Instance",
	abstract = true,
	methods = remoteMethods,
	events = "OnServerEvent OnClientEvent",
	eventCtx = { OnServerEvent = "server", OnClientEvent = "client" },
})
def("RemoteEvent", { base = "BaseRemoteEvent" })
def("UnreliableRemoteEvent", { base = "BaseRemoteEvent" })
def("BindableEvent", {
	base = "Instance",
	methods = {
		Fire = function(o, ...)
			fire(getSignal(o, "Event"), ...)
		end,
	},
	events = "Event",
})
def("BindableFunction", {
	base = "Instance",
	props = P("OnInvoke:Function"),
	methods = {
		Invoke = function(o, ...)
			local f = rawget(o, "__props").OnInvoke
			if not f then
				error("BindableFunction:Invoke: no OnInvoke callback", 2)
			end
			return f(...)
		end,
	},
})

---------------------------------------------------------------- Joints
MOCK._joints = {}
local function registerJoint(o)
	table.insert(MOCK._joints, o)
end
def("JointInstance", {
	base = "Instance",
	abstract = true,
	props = P("C0:CFrame C1:CFrame Part0:Instance:BasePart Part1:Instance:BasePart Enabled:boolean"),
	ro = { Active = true },
	defaults = { C0 = CFrame.identity, C1 = CFrame.identity, Enabled = true },
	get = {
		Active = function(o)
			local pr = rawget(o, "__props")
			return pr.Enabled ~= false and pr.Part0 ~= nil and pr.Part1 ~= nil and Inst.IsDescendantOf(pr.Part0, workspace) and Inst.IsDescendantOf(pr.Part1, workspace)
		end,
	},
	register = registerJoint,
})
def("Weld", { base = "JointInstance" })
def("ManualWeld", { base = "JointInstance" })
def("Motor", { base = "JointInstance", props = P("MaxVelocity:number DesiredAngle:number CurrentAngle:number"), defaults = { MaxVelocity = 0, DesiredAngle = 0, CurrentAngle = 0 } })
def("Motor6D", {
	base = "Motor",
	props = P("Transform:CFrame"),
	defaults = { Transform = CFrame.identity },
	set = {
		Transform = function(o, v)
			local int = internal(o)
			int.writer = curCtx -- last writer of Transform: a script ("client"/"server"/"edit") or "animator"
			int.writeFrame = MOCK.frame
			rawget(o, "__props").Transform = v
		end,
	},
})
local function wcCapture(o)
	local pr = rawget(o, "__props")
	if pr.Part0 and pr.Part1 then
		local int = internal(o)
		int.cloneable = true
		int.offset = pr.Part0.CFrame:Inverse() * pr.Part1.CFrame
	end
end
def("WeldConstraint", {
	base = "Instance",
	props = P("Part0:Instance:BasePart Part1:Instance:BasePart Enabled:boolean"),
	ro = { Active = true },
	defaults = { Enabled = true },
	get = {
		Active = function(o)
			local pr = rawget(o, "__props")
			return pr.Enabled ~= false and pr.Part0 ~= nil and pr.Part1 ~= nil
		end,
	},
	set = {
		Part0 = function(o, v)
			store(o, "Part0", v)
			wcCapture(o)
		end,
		Part1 = function(o, v)
			store(o, "Part1", v)
			wcCapture(o)
		end,
		Enabled = function(o, v)
			store(o, "Enabled", v)
			if v then
				wcCapture(o)
			end
		end,
	},
	register = registerJoint,
})

---------------------------------------------------------------- Tools, accessories, clothing
local function gripCF(o)
	return rawget(o, "__props").Grip or CFrame.identity
end
def("BackpackItem", { base = "Model", abstract = true, props = P("TextureId:string"), defaults = { TextureId = "" } })
def("Tool", {
	base = "BackpackItem",
	props = P(
		"Grip:CFrame GripPos:Vector3 GripForward:Vector3 GripRight:Vector3 GripUp:Vector3 RequiresHandle:boolean "
			.. "CanBeDropped:boolean ToolTip:string Enabled:boolean ManualActivationOnly:boolean"
	),
	defaults = { Grip = CFrame.identity, RequiresHandle = true, CanBeDropped = true, ToolTip = "", Enabled = true, ManualActivationOnly = false },
	get = {
		GripPos = function(o)
			return gripCF(o).Position
		end,
		GripForward = function(o)
			return -gripCF(o).ZVector
		end,
		GripRight = function(o)
			return gripCF(o).XVector
		end,
		GripUp = function(o)
			return gripCF(o).YVector
		end,
	},
	set = {
		GripPos = function(o, v)
			o.Grip = CFrame.new(v) * gripCF(o).Rotation
		end,
		GripForward = function(o, v)
			local g = gripCF(o)
			o.Grip = CFrame.fromMatrix(g.Position, g.XVector, g.YVector, -v.Unit)
		end,
		GripRight = function(o, v)
			local g = gripCF(o)
			o.Grip = CFrame.fromMatrix(g.Position, v.Unit, g.YVector)
		end,
		GripUp = function(o, v)
			local g = gripCF(o)
			o.Grip = CFrame.fromMatrix(g.Position, g.XVector, v.Unit)
		end,
	},
	methods = {
		Activate = function(o)
			fireIf(o, "Activated")
		end,
		Deactivate = function(o)
			fireIf(o, "Deactivated")
		end,
	},
	events = "Activated Deactivated Equipped Unequipped",
	onParent = function(o, new, old)
		MOCK.__toolParented(o, new, old)
	end,
})
def("Backpack", { base = "Instance" })
def("StarterGear", { base = "Instance" })
def("Accoutrement", { base = "Instance", props = P("AttachmentPoint:CFrame"), defaults = { AttachmentPoint = CFrame.identity } })
def("Accessory", { base = "Accoutrement", props = P("AccessoryType:Enum:AccessoryType"), defaults = { AccessoryType = Enum.AccessoryType.Unknown } })
def("Hat", { base = "Accoutrement" })
def("BodyColors", {
	base = "Instance",
	props = P("HeadColor3:Color3 TorsoColor3:Color3 LeftArmColor3:Color3 RightArmColor3:Color3 LeftLegColor3:Color3 RightLegColor3:Color3"),
	defaults = {
		HeadColor3 = rgb(234, 184, 146),
		TorsoColor3 = rgb(13, 105, 172),
		LeftArmColor3 = rgb(234, 184, 146),
		RightArmColor3 = rgb(234, 184, 146),
		LeftLegColor3 = rgb(40, 127, 71),
		RightLegColor3 = rgb(40, 127, 71),
	},
})
def("Clothing", { base = "Instance", abstract = true, props = P("Color3:Color3"), defaults = { Color3 = WHITE } })
def("Shirt", { base = "Clothing", props = P("ShirtTemplate:string"), defaults = { ShirtTemplate = "" } })
def("Pants", { base = "Clothing", props = P("PantsTemplate:string"), defaults = { PantsTemplate = "" } })

---------------------------------------------------------------- Camera
local function camSetFov(o, v)
	if v < 1 or v > 120 then
		mockWarn("Camera.FieldOfView " .. tostring(v) .. " is outside 1..120 and gets clamped")
		v = math.clamp(v, 1, 120)
	end
	store(o, "FieldOfView", v)
end
local function camRay(o, x, y, depth, inset)
	local vs = MOCK.viewportSize
	local cf = o.CFrame
	local fov = rad(o.FieldOfView)
	local th = math.tan(fov / 2)
	local aspect = vs.X / vs.Y
	local nx = (x / vs.X) * 2 - 1
	local ny = 1 - ((y + inset) / vs.Y) * 2
	local dir = (cf.LookVector + cf.RightVector * (nx * th * aspect) + cf.UpVector * (ny * th)).Unit
	return Ray.new(cf.Position + dir * (depth or 0), dir)
end
local function camProject(o, p, inset)
	local vs = MOCK.viewportSize
	local cf = o.CFrame
	local rel = cf:PointToObjectSpace(p)
	local th = math.tan(rad(o.FieldOfView) / 2)
	local aspect = vs.X / vs.Y
	local z = -rel.Z
	local nx = rel.X / (math.max(math.abs(z), 1e-6) * th * aspect)
	local ny = rel.Y / (math.max(math.abs(z), 1e-6) * th)
	local sx = (nx + 1) / 2 * vs.X
	local sy = (1 - ny) / 2 * vs.Y - inset
	local onScreen = z > 0 and math.abs(nx) <= 1 and math.abs(ny) <= 1
	return Vector3.new(sx, sy, z), onScreen
end
def("Camera", {
	base = "PVInstance",
	props = P(
		"CFrame:CFrame Focus:CFrame FieldOfView:number CameraType:Enum:CameraType CameraSubject:Instance "
			.. "FieldOfViewMode:Enum:FieldOfViewMode DiagonalFieldOfView:number MaxAxisFieldOfView:number HeadLocked:boolean "
			.. "HeadScale:number VRTiltAndRollEnabled:boolean"
	),
	ro = { ViewportSize = true, NearPlaneZ = true },
	defaults = {
		CFrame = CFrame.new(0, 20, 20) * CFrame.Angles(-math.pi / 4, 0, 0),
		Focus = CFrame.identity,
		FieldOfView = 70,
		CameraType = Enum.CameraType.Fixed,
		FieldOfViewMode = Enum.FieldOfViewMode.Vertical,
		HeadLocked = true,
		HeadScale = 1,
		VRTiltAndRollEnabled = false,
		NearPlaneZ = -0.1,
	},
	get = {
		ViewportSize = function()
			return MOCK.viewportSize
		end,
		DiagonalFieldOfView = function(o)
			local vs = MOCK.viewportSize
			local th = math.tan(rad(o.FieldOfView) / 2)
			local d = math.sqrt(vs.X * vs.X + vs.Y * vs.Y) / vs.Y
			return deg(2 * math.atan(th * d))
		end,
		MaxAxisFieldOfView = function(o)
			local vs = MOCK.viewportSize
			local th = math.tan(rad(o.FieldOfView) / 2)
			return deg(2 * math.atan(th * math.max(vs.X, vs.Y) / vs.Y))
		end,
	},
	set = {
		FieldOfView = camSetFov,
		DiagonalFieldOfView = function(o, v)
			local vs = MOCK.viewportSize
			local d = math.sqrt(vs.X * vs.X + vs.Y * vs.Y) / vs.Y
			camSetFov(o, deg(2 * math.atan(math.tan(rad(v) / 2) / d)))
		end,
		MaxAxisFieldOfView = function(o, v)
			local vs = MOCK.viewportSize
			camSetFov(o, deg(2 * math.atan(math.tan(rad(v) / 2) / (math.max(vs.X, vs.Y) / vs.Y))))
		end,
		CFrame = function(o, v)
			store(o, "CFrame", v)
		end,
	},
	methods = {
		ScreenPointToRay = function(o, x, y, depth)
			return camRay(o, x, y, depth, MOCK.guiInset)
		end,
		ViewportPointToRay = function(o, x, y, depth)
			return camRay(o, x, y, depth, 0)
		end,
		WorldToScreenPoint = function(o, p)
			return camProject(o, p, MOCK.guiInset)
		end,
		WorldToViewportPoint = function(o, p)
			return camProject(o, p, 0)
		end,
		GetRenderCFrame = function(o)
			return o.CFrame
		end,
		GetPartsObscuringTarget = function()
			return {}
		end,
		GetPivot = function(o)
			return o.CFrame
		end,
		PivotTo = function(o, cf)
			o.CFrame = cf
		end,
	},
	events = "InterpolationFinished",
})

---------------------------------------------------------------- GUI
def("GuiBase", { base = "Instance", abstract = true })
local function guiRect(o)
	-- absolute (x, y, w, h) like Roblox's layout for the simple cases (no layouts, no UIScale)
	local c = defOf(o)
	if c.ancestors.ScreenGui then
		local vs = MOCK.viewportSize
		if rawget(o, "__props").IgnoreGuiInset then
			return 0, 0, vs.X, vs.Y
		end
		return 0, MOCK.guiInset, vs.X, vs.Y - MOCK.guiInset
	elseif c.ancestors.SurfaceGui then
		local s = o.CanvasSize
		return 0, 0, s.X, s.Y
	elseif c.ancestors.BillboardGui then
		local s = o.Size
		return 0, 0, s.X.Offset, s.Y.Offset
	elseif not c.ancestors.GuiObject then
		return 0, 0, 0, 0
	end
	local par = parentOf(o)
	local px, py, pw, ph = 0, 0, 0, 0
	if par and defOf(par).ancestors.GuiBase2d then
		px, py, pw, ph = guiRect(par)
	end
	local size, pos, anchor = o.Size, o.Position, o.AnchorPoint
	local sc = o.SizeConstraint.Name
	local bw = sc == "RelativeYY" and ph or pw
	local bh = sc == "RelativeXX" and pw or ph
	local w = bw * size.X.Scale + size.X.Offset
	local h = bh * size.Y.Scale + size.Y.Offset
	local ar = Inst.FindFirstChildOfClass(o, "UIAspectRatioConstraint")
	if ar then
		local r = ar.AspectRatio
		if w / math.max(h, 1e-9) > r then
			w = h * r
		else
			h = w / r
		end
	end
	local x = px + pw * pos.X.Scale + pos.X.Offset - anchor.X * w
	local y = py + ph * pos.Y.Scale + pos.Y.Offset - anchor.Y * h
	return x, y, w, h
end
MOCK.guiRect = guiRect
def("GuiBase2d", {
	base = "GuiBase",
	abstract = true,
	props = P("AutoLocalize:boolean RootLocalizationTable:Instance SelectionGroup:boolean"),
	ro = { AbsolutePosition = true, AbsoluteSize = true, AbsoluteRotation = true },
	defaults = { AutoLocalize = true, SelectionGroup = false },
	get = {
		AbsolutePosition = function(o)
			local x, y = guiRect(o)
			return Vector2.new(x, y)
		end,
		AbsoluteSize = function(o)
			local _, _, w, h = guiRect(o)
			return Vector2.new(w, h)
		end,
		AbsoluteRotation = function(o)
			local r = 0
			local a = o
			while a and defOf(a).ancestors.GuiObject do
				r += a.Rotation
				a = parentOf(a)
			end
			return r
		end,
	},
})
def("LayerCollector", {
	base = "GuiBase2d",
	abstract = true,
	props = P("Enabled:boolean ResetOnSpawn:boolean ZIndexBehavior:Enum:ZIndexBehavior"),
	defaults = { Enabled = true, ResetOnSpawn = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling },
})
def("ScreenGui", {
	base = "LayerCollector",
	props = P("DisplayOrder:int IgnoreGuiInset:boolean ScreenInsets:Enum:ScreenInsets ClipToDeviceSafeArea:boolean SafeAreaCompatibility:Enum:SafeAreaCompatibility"),
	defaults = {
		DisplayOrder = 0,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ClipToDeviceSafeArea = true,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension,
	},
})
def("SurfaceGuiBase", { base = "LayerCollector", abstract = true, props = P("Adornee:Instance Face:Enum:NormalId Active:boolean"), defaults = { Face = Enum.NormalId.Front, Active = true } })
def("SurfaceGui", {
	base = "SurfaceGuiBase",
	props = P(
		"CanvasSize:Vector2 LightInfluence:number SizingMode:Enum:SurfaceGuiSizingMode PixelsPerStud:number AlwaysOnTop:boolean "
			.. "Brightness:number ClipsDescendants:boolean ZOffset:number ToolPunchThroughDistance:number MaxDistance:number"
	),
	defaults = {
		CanvasSize = Vector2.new(800, 600),
		LightInfluence = 1,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		PixelsPerStud = 50,
		AlwaysOnTop = false,
		Brightness = 1,
		ClipsDescendants = true,
		ZOffset = 0,
		MaxDistance = 0,
	},
})
def("BillboardGui", {
	base = "LayerCollector",
	props = P(
		"Adornee:Instance AlwaysOnTop:boolean Size:UDim2 StudsOffset:Vector3 StudsOffsetWorldSpace:Vector3 ExtentsOffset:Vector3 "
			.. "ExtentsOffsetWorldSpace:Vector3 MaxDistance:number LightInfluence:number Brightness:number ClipsDescendants:boolean "
			.. "SizeOffset:Vector2 Active:boolean"
	),
	defaults = {
		AlwaysOnTop = false,
		Size = UDim2.new(),
		StudsOffset = Vector3.zero,
		StudsOffsetWorldSpace = Vector3.zero,
		ExtentsOffset = Vector3.zero,
		ExtentsOffsetWorldSpace = Vector3.zero,
		MaxDistance = math.huge,
		LightInfluence = 0,
		Brightness = 1,
		ClipsDescendants = false,
		SizeOffset = Vector2.zero,
		Active = false,
	},
})
local GUIOBJECT_PROPS = P(
	"Active:boolean AnchorPoint:Vector2 AutomaticSize:Enum:AutomaticSize BackgroundColor3:Color3 BackgroundTransparency:number "
		.. "BorderColor3:Color3 BorderMode:Enum:BorderMode BorderSizePixel:int ClipsDescendants:boolean Interactable:boolean "
		.. "LayoutOrder:int Position:UDim2 Rotation:number Selectable:boolean SelectionImageObject:Instance SelectionOrder:int "
		.. "Size:UDim2 SizeConstraint:Enum:SizeConstraint Visible:boolean ZIndex:int Transparency:number"
)
def("GuiObject", {
	base = "GuiBase2d",
	abstract = true,
	props = GUIOBJECT_PROPS,
	defaults = {
		Active = false,
		AnchorPoint = Vector2.zero,
		AutomaticSize = Enum.AutomaticSize.None,
		BackgroundColor3 = rgb(163, 162, 165),
		BackgroundTransparency = 0,
		BorderColor3 = rgb(27, 42, 53),
		BorderMode = Enum.BorderMode.Outline,
		BorderSizePixel = 1,
		ClipsDescendants = false,
		Interactable = true,
		LayoutOrder = 0,
		Position = UDim2.new(),
		Rotation = 0,
		Selectable = false,
		SelectionOrder = 0,
		Size = UDim2.new(0, 100, 0, 100),
		SizeConstraint = Enum.SizeConstraint.RelativeXY,
		Visible = true,
		ZIndex = 1,
	},
	get = {
		Transparency = function(o)
			return o.BackgroundTransparency
		end,
	},
	set = {
		Transparency = function(o, v)
			o.BackgroundTransparency = v
		end,
	},
	events = "InputBegan InputEnded InputChanged MouseEnter MouseLeave MouseMoved SelectionGained SelectionLost",
})
def("Frame", { base = "GuiObject", props = P("Style:Enum:FrameStyle"), defaults = { Style = Enum.FrameStyle.Custom } })
def("CanvasGroup", { base = "GuiObject", props = P("GroupColor3:Color3 GroupTransparency:number"), defaults = { GroupColor3 = WHITE, GroupTransparency = 0 } })
local TEXT_PROPS = P(
	"Text:string TextColor3:Color3 TextSize:number TextScaled:boolean TextWrapped:boolean TextXAlignment:Enum:TextXAlignment "
		.. "TextYAlignment:Enum:TextYAlignment TextTransparency:number TextStrokeColor3:Color3 TextStrokeTransparency:number "
		.. "Font:Enum:Font FontFace:Font LineHeight:number RichText:boolean MaxVisibleGraphemes:int TextTruncate:Enum:TextTruncate "
		.. "TextDirection:Enum:TextDirection"
)
local TEXT_DEFAULTS = {
	Text = "Label",
	TextColor3 = rgb(27, 42, 53),
	TextSize = 14,
	TextScaled = false,
	TextWrapped = false,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	TextTransparency = 0,
	TextStrokeColor3 = BLACK,
	TextStrokeTransparency = 1,
	Font = Enum.Font.Legacy,
	LineHeight = 1,
	RichText = false,
	MaxVisibleGraphemes = -1,
	TextTruncate = Enum.TextTruncate.None,
	TextDirection = Enum.TextDirection.Auto,
}
local TEXT_GET = {
	ContentText = function(o)
		return o.Text
	end,
	TextBounds = function(o)
		return Vector2.new(#o.Text * o.TextSize * 0.5, o.TextSize)
	end,
	TextFits = function()
		return true
	end,
	FontFace = function(o)
		local f = rawget(o, "__props").FontFace
		return f or Font.fromEnum(o.Font)
	end,
}
def("TextLabel", { base = "GuiObject", props = TEXT_PROPS, ro = { ContentText = true, TextBounds = true, TextFits = true }, defaults = TEXT_DEFAULTS, get = TEXT_GET })
def("GuiButton", {
	base = "GuiObject",
	abstract = true,
	props = P("AutoButtonColor:boolean Modal:boolean Selected:boolean Style:Enum:ButtonStyle"),
	defaults = { AutoButtonColor = true, Modal = false, Selected = false, Style = Enum.ButtonStyle.Custom, Active = true, Selectable = true },
	events = "Activated MouseButton1Click MouseButton1Down MouseButton1Up MouseButton2Click MouseButton2Down MouseButton2Up",
})
def("TextButton", { base = "GuiButton", props = TEXT_PROPS, ro = { ContentText = true, TextBounds = true, TextFits = true }, defaults = merge(TEXT_DEFAULTS, { Text = "Button" }), get = TEXT_GET })
def("TextBox", {
	base = "GuiObject",
	props = merge(TEXT_PROPS, P("ClearTextOnFocus:boolean PlaceholderText:string PlaceholderColor3:Color3 TextEditable:boolean MultiLine:boolean CursorPosition:int")),
	ro = { ContentText = true, TextBounds = true, TextFits = true },
	defaults = merge(TEXT_DEFAULTS, { Text = "TextBox", ClearTextOnFocus = true, PlaceholderText = "", PlaceholderColor3 = rgb(178, 178, 178), TextEditable = true, MultiLine = false, CursorPosition = 1 }),
	get = TEXT_GET,
	methods = {
		CaptureFocus = function() end,
		ReleaseFocus = function() end,
		IsFocused = function()
			return false
		end,
	},
	events = "FocusLost Focused",
})
local IMAGE_PROPS = P(
	"Image:string ImageColor3:Color3 ImageTransparency:number ImageRectOffset:Vector2 ImageRectSize:Vector2 "
		.. "ScaleType:Enum:ScaleType SliceCenter:Rect SliceScale:number TileSize:UDim2 ResampleMode:Enum:ResamplerMode"
)
local IMAGE_DEFAULTS = {
	Image = "",
	ImageColor3 = WHITE,
	ImageTransparency = 0,
	ImageRectOffset = Vector2.zero,
	ImageRectSize = Vector2.zero,
	ScaleType = Enum.ScaleType.Stretch,
	SliceCenter = Rect.new(0, 0, 0, 0),
	SliceScale = 1,
	TileSize = UDim2.new(1, 0, 1, 0),
	ResampleMode = Enum.ResamplerMode.Default,
}
local IMAGE_GET = {
	IsLoaded = function(o)
		return o.Image ~= ""
	end,
}
def("ImageLabel", { base = "GuiObject", props = IMAGE_PROPS, ro = { IsLoaded = true }, defaults = IMAGE_DEFAULTS, get = IMAGE_GET })
def("ImageButton", { base = "GuiButton", props = IMAGE_PROPS, ro = { IsLoaded = true }, defaults = IMAGE_DEFAULTS, get = IMAGE_GET })
def("ViewportFrame", {
	base = "GuiObject",
	props = P("CurrentCamera:Instance:Camera Ambient:Color3 LightColor:Color3 LightDirection:Vector3 ImageColor3:Color3 ImageTransparency:number"),
	defaults = {
		Ambient = rgb(200, 200, 200),
		LightColor = rgb(140, 140, 140),
		LightDirection = Vector3.new(-1, -1, -1),
		ImageColor3 = WHITE,
		ImageTransparency = 0,
	},
})
def("UIBase", { base = "Instance", abstract = true })
def("UIComponent", { base = "UIBase", abstract = true })
def("UIConstraint", { base = "UIComponent", abstract = true })
def("UIAspectRatioConstraint", {
	base = "UIConstraint",
	props = P("AspectRatio:number AspectType:Enum:AspectType DominantAxis:Enum:DominantAxis"),
	defaults = { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize, DominantAxis = Enum.DominantAxis.Width },
	set = {
		AspectRatio = function(o, v)
			if v <= 0 then
				error("UIAspectRatioConstraint.AspectRatio must be positive", 3)
			end
			store(o, "AspectRatio", v)
		end,
	},
})
def("UISizeConstraint", { base = "UIConstraint", props = P("MaxSize:Vector2 MinSize:Vector2"), defaults = { MaxSize = Vector2.new(math.huge, math.huge), MinSize = Vector2.zero } })
def("UITextSizeConstraint", { base = "UIConstraint", props = P("MaxTextSize:int MinTextSize:int"), defaults = { MaxTextSize = 100, MinTextSize = 1 } })
def("UIGradient", {
	base = "UIComponent",
	props = P("Color:ColorSequence Transparency:NumberSequence Rotation:number Offset:Vector2 Enabled:boolean"),
	defaults = { Color = ColorSequence.new(WHITE), Transparency = NumberSequence.new(0), Rotation = 0, Offset = Vector2.zero, Enabled = true },
})
def("UICorner", { base = "UIComponent", props = P("CornerRadius:UDim"), defaults = { CornerRadius = UDim.new(0, 8) } })
def("UIStroke", {
	base = "UIComponent",
	props = P("Color:Color3 Thickness:number Transparency:number ApplyStrokeMode:Enum:ApplyStrokeMode LineJoinMode:Enum:LineJoinMode Enabled:boolean"),
	defaults = { Color = BLACK, Thickness = 1, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round, Enabled = true },
})
def("UIScale", { base = "UIComponent", props = P("Scale:number"), defaults = { Scale = 1 } })
def("UIPadding", {
	base = "UIComponent",
	props = P("PaddingTop:UDim PaddingBottom:UDim PaddingLeft:UDim PaddingRight:UDim"),
	defaults = { PaddingTop = UDim.new(), PaddingBottom = UDim.new(), PaddingLeft = UDim.new(), PaddingRight = UDim.new() },
})
def("UIListLayout", {
	base = "UIComponent",
	props = P("Padding:UDim FillDirection:Enum:FillDirection SortOrder:Enum:SortOrder HorizontalAlignment:Enum:HorizontalAlignment VerticalAlignment:Enum:VerticalAlignment Wraps:boolean"),
	defaults = {
		Padding = UDim.new(),
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Wraps = false,
	},
})

---------------------------------------------------------------- Characters
def("Animation", { base = "Instance", props = P("AnimationId:string"), defaults = { AnimationId = "" } })
MOCK._animators = {}
def("Animator", {
	base = "Instance",
	register = function(o)
		table.insert(MOCK._animators, o)
	end,
	methods = {}, -- filled in by the simulation section
	events = "AnimationPlayed",
})
def("AnimationController", { base = "Instance", methods = {}, events = "AnimationPlayed" })
def("AnimationTrack", {
	base = "Instance",
	notCreatable = true,
	props = P("Looped:boolean Priority:Enum:AnimationPriority TimePosition:number"),
	ro = { IsPlaying = true, Length = true, Speed = true, WeightCurrent = true, WeightTarget = true, Animation = true },
	defaults = { Looped = true, Priority = Enum.AnimationPriority.Core, TimePosition = 0 },
	methods = {}, -- filled in by the simulation section
	events = "Stopped Ended DidLoop KeyframeReached",
})
def("Humanoid", {
	base = "Instance",
	props = P(
		"HipHeight:number WalkSpeed:number JumpPower:number JumpHeight:number UseJumpPower:boolean AutoRotate:boolean "
			.. "PlatformStand:boolean Sit:boolean Jump:boolean Health:number MaxHealth:number DisplayName:string "
			.. "CameraOffset:Vector3 AutoJumpEnabled:boolean BreakJointsOnDeath:boolean RequiresNeck:boolean "
			.. "EvaluateStateMachine:boolean DisplayDistanceType:Enum:HumanoidDisplayDistanceType "
			.. "HealthDisplayType:Enum:HumanoidHealthDisplayType HealthDisplayDistance:number NameDisplayDistance:number "
			.. "MaxSlopeAngle:number AutomaticScalingEnabled:boolean RigType:Enum:HumanoidRigType WalkToPoint:Vector3 "
			.. "WalkToPart:Instance:BasePart TargetPoint:Vector3"
	),
	ro = { RootPart = true, MoveDirection = true, FloorMaterial = true, SeatPart = true },
	defaults = {
		HipHeight = 2,
		WalkSpeed = 16,
		JumpPower = 50,
		JumpHeight = 7.2,
		UseJumpPower = false,
		AutoRotate = true,
		PlatformStand = false,
		Sit = false,
		Jump = false,
		Health = 100,
		MaxHealth = 100,
		DisplayName = "",
		CameraOffset = Vector3.zero,
		AutoJumpEnabled = true,
		BreakJointsOnDeath = true,
		RequiresNeck = true,
		EvaluateStateMachine = true,
		DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer,
		HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged,
		HealthDisplayDistance = 100,
		NameDisplayDistance = 100,
		MaxSlopeAngle = 89,
		AutomaticScalingEnabled = true,
		RigType = Enum.HumanoidRigType.R15,
		WalkToPoint = Vector3.zero,
		TargetPoint = Vector3.zero,
		MoveDirection = Vector3.zero,
	},
	get = {
		RootPart = function(o)
			local m = parentOf(o)
			return m and Inst.FindFirstChild(m, "HumanoidRootPart") or nil
		end,
		FloorMaterial = function(o)
			local st = internal(o).state
			if st == nil or st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics or st == Enum.HumanoidStateType.Landed then
				return Enum.Material.Grass
			end
			return Enum.Material.Air
		end,
	},
	methods = {}, -- filled in by the simulation section
	set = {}, -- filled in by the simulation section
	events = "Died StateChanged HealthChanged Running Jumping FreeFalling Climbing GettingUp FallingDown Seated PlatformStanding Ragdoll Swimming Touched MoveToFinished AnimationPlayed",
})

---------------------------------------------------------------- Players
def("Player", {
	base = "Instance",
	notCreatable = true,
	props = P(
		"Character:Instance:Model CameraMode:Enum:CameraMode CameraMaxZoomDistance:number CameraMinZoomDistance:number "
			.. "DevCameraOcclusionMode:Enum:DevCameraOcclusionMode RespawnLocation:Instance:SpawnLocation Team:Instance TeamColor "
			.. "Neutral:boolean ReplicationFocus:Instance AutoJumpEnabled:boolean HealthDisplayDistance:number "
			.. "NameDisplayDistance:number DisplayName:string"
	),
	ro = { UserId = true, AccountAge = true, MembershipType = true, FollowUserId = true, LocaleId = true },
	defaults = {
		CameraMode = Enum.CameraMode.Classic,
		CameraMaxZoomDistance = 400,
		CameraMinZoomDistance = 0.5,
		DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom,
		Neutral = true,
		AutoJumpEnabled = true,
		HealthDisplayDistance = 100,
		NameDisplayDistance = 100,
		AccountAge = 365,
		FollowUserId = 0,
		LocaleId = "en-us",
	},
	get = {
		UserId = function(o)
			return internal(o).userId or 1
		end,
	},
	methods = {}, -- filled in by the simulation section
	events = "CharacterAdded CharacterRemoving CharacterAppearanceLoaded Chatted Idled",
})
def("PlayerScripts", { base = "Instance" })
def("BasePlayerGui", { base = "Instance", abstract = true })
def("PlayerGui", { base = "BasePlayerGui", props = P("ScreenOrientation:Enum:ScreenOrientation SelectionImageObject:Instance"), defaults = { ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor } })
def("StarterPlayerScripts", { base = "Instance", notCreatable = true })
def("StarterCharacterScripts", { base = "Instance", notCreatable = true })
def("InputObject", {
	base = "Instance",
	notCreatable = true,
	props = P("KeyCode:Enum:KeyCode UserInputType:Enum:UserInputType UserInputState:Enum:UserInputState Position:Vector3 Delta:Vector3"),
	defaults = {
		KeyCode = Enum.KeyCode.Unknown,
		UserInputType = Enum.UserInputType.None,
		UserInputState = Enum.UserInputState.None,
		Position = Vector3.zero,
		Delta = Vector3.zero,
	},
	methods = {
		IsModifierKeyDown = function()
			return false
		end,
	},
})
def("Tween", {
	base = "Instance",
	notCreatable = true,
	ro = { Instance = true, TweenInfo = true, PlaybackState = true },
	methods = {}, -- filled in by the simulation section
	events = "Completed",
})

---------------------------------------------------------------- Services
def("DataModel", {
	base = "Instance",
	service = true,
	ro = { PlaceId = true, GameId = true, JobId = true, CreatorId = true, PlaceVersion = true, CreatorType = true },
	defaults = { PlaceId = 0, GameId = 0, JobId = "", CreatorId = 0, PlaceVersion = 0 },
	methods = {}, -- GetService etc. below
	events = "Loaded Close",
})
def("Workspace", {
	base = "WorldRoot",
	service = true,
	props = P(
		"CurrentCamera:Instance:Camera GlobalWind:Vector3 Gravity:number StreamingEnabled:boolean StreamingMinRadius:number "
			.. "StreamingTargetRadius:number StreamingIntegrityMode:Enum:StreamingIntegrityMode StreamOutBehavior:Enum:StreamOutBehavior "
			.. "FallenPartsDestroyHeight:number AirDensity:number AllowThirdPartySales:boolean"
	),
	ro = { DistributedGameTime = true, Terrain = true },
	defaults = {
		GlobalWind = Vector3.zero,
		Gravity = 196.2,
		StreamingEnabled = false,
		StreamingMinRadius = 64,
		StreamingTargetRadius = 1024,
		StreamingIntegrityMode = Enum.StreamingIntegrityMode.Default,
		StreamOutBehavior = Enum.StreamOutBehavior.Default,
		FallenPartsDestroyHeight = -500,
		AirDensity = 0.0012,
		AllowThirdPartySales = false,
	},
	get = {
		DistributedGameTime = function()
			return MOCK.clock
		end,
	},
	methods = {}, -- Raycast etc. below
})
local permissiveServices = { "ChangeHistoryService", "StarterPlayer", "Terrain" }
for _, n in ipairs(permissiveServices) do
	def(n, { base = "Instance", service = true, permissive = true })
end
for _, n in ipairs({ "ReplicatedStorage", "ReplicatedFirst", "ServerStorage", "ServerScriptService", "StarterPack", "Teams" }) do
	def(n, { base = "Instance", service = true })
end
def("RunService", { base = "Instance", service = true, methods = {}, events = "RenderStepped PreRender PreAnimation PreSimulation Stepped PostSimulation Heartbeat", eventCtx = { RenderStepped = "client", PreRender = "client" } })
def("Players", {
	base = "Instance",
	service = true,
	props = P("CharacterAutoLoads:boolean RespawnTime:number"),
	ro = { LocalPlayer = true, MaxPlayers = true },
	defaults = { CharacterAutoLoads = true, RespawnTime = 5, MaxPlayers = 50 },
	get = {
		LocalPlayer = function()
			if curCtx == "server" then
				return nil
			end
			return MOCK.localPlayer
		end,
	},
	methods = {},
	events = "PlayerAdded PlayerRemoving",
})
def("TweenService", { base = "Instance", service = true, methods = {} })
def("UserInputService", {
	base = "Instance",
	service = true,
	props = P("MouseBehavior:Enum:MouseBehavior MouseIconEnabled:boolean MouseDeltaSensitivity:number ModalEnabled:boolean"),
	ro = {
		KeyboardEnabled = true, MouseEnabled = true, TouchEnabled = true, GamepadEnabled = true, AccelerometerEnabled = true,
		GyroscopeEnabled = true, VREnabled = true, OnScreenKeyboardVisible = true,
	},
	defaults = {
		MouseBehavior = Enum.MouseBehavior.Default,
		MouseIconEnabled = true,
		MouseDeltaSensitivity = 1,
		ModalEnabled = false,
		KeyboardEnabled = true,
		MouseEnabled = true,
		TouchEnabled = false,
		GamepadEnabled = false,
		AccelerometerEnabled = false,
		GyroscopeEnabled = false,
		VREnabled = false,
		OnScreenKeyboardVisible = false,
	},
	methods = {},
	events = "InputBegan InputEnded InputChanged TouchStarted TouchEnded TouchMoved TouchTap LastInputTypeChanged WindowFocused WindowFocusReleased JumpRequest TextBoxFocused TextBoxFocusReleased",
	eventCtx = { InputBegan = "client", InputEnded = "client", InputChanged = "client" },
})
def("ContextActionService", { base = "Instance", service = true, methods = {}, events = "LocalToolEquipped LocalToolUnequipped" })
def("StarterGui", {
	base = "Instance",
	service = true,
	props = P("ShowDevelopmentGui:boolean ScreenOrientation:Enum:ScreenOrientation ResetPlayerGuiOnSpawn:boolean"),
	defaults = { ShowDevelopmentGui = true, ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor, ResetPlayerGuiOnSpawn = true },
	methods = {},
})
def("GuiService", {
	base = "Instance",
	service = true,
	props = P("AutoSelectGuiEnabled:boolean GuiNavigationEnabled:boolean SelectedObject:Instance TouchControlsEnabled:boolean"),
	ro = { MenuIsOpen = true, TopbarInset = true },
	defaults = { AutoSelectGuiEnabled = true, GuiNavigationEnabled = true, TouchControlsEnabled = true, MenuIsOpen = false },
	get = {
		TopbarInset = function()
			return Rect.new(0, 0, MOCK.viewportSize.X, MOCK.guiInset)
		end,
	},
	methods = {
		GetGuiInset = function()
			return Vector2.new(0, MOCK.guiInset), Vector2.zero
		end,
		IsTenFootInterface = function()
			return false
		end,
	},
	events = "MenuOpened MenuClosed",
})
def("SoundService", {
	base = "Instance",
	service = true,
	props = P("AmbientReverb:Enum:ReverbType DistanceFactor:number DopplerScale:number RolloffScale:number RespectFilteringEnabled:boolean"),
	defaults = { AmbientReverb = Enum.ReverbType.NoReverb, DistanceFactor = 3.33, DopplerScale = 1, RolloffScale = 1, RespectFilteringEnabled = true },
	methods = {
		PlayLocalSound = function(_, sound)
			assert(isInstance(sound) and sound:IsA("Sound"), "PlayLocalSound expects a Sound")
			MOCK.soundLog[#MOCK.soundLog + 1] = { id = sound.SoundId, t = MOCK.clock, name = sound.Name, ["local"] = true }
		end,
	},
})
def("Debris", {
	base = "Instance",
	service = true,
	props = P("MaxItems:int"),
	defaults = { MaxItems = 1000 },
	methods = {
		AddItem = function(_, item, lifetime)
			assert(isInstance(item), "Debris:AddItem expects an Instance")
			lifetime = lifetime or 10
			task.delay(lifetime, function()
				if not rawget(item, "__destroyed") then
					item:Destroy()
				end
			end)
		end,
	},
})
def("CollectionService", {
	base = "Instance",
	service = true,
	methods = {
		AddTag = function(_, o, tag)
			Inst.AddTag(o, tag)
		end,
		RemoveTag = function(_, o, tag)
			Inst.RemoveTag(o, tag)
		end,
		HasTag = function(_, o, tag)
			return Inst.HasTag(o, tag)
		end,
		GetTags = function(_, o)
			return Inst.GetTags(o)
		end,
		GetTagged = function(_, tag)
			local out = {}
			for o in pairs(tagged[tag] or {}) do
				if not rawget(o, "__destroyed") then
					table.insert(out, o)
				end
			end
			return out
		end,
		GetInstanceAddedSignal = function(self, tag)
			return getSignal(self, "tagAdded:" .. tag)
		end,
		GetInstanceRemovedSignal = function(self, tag)
			return getSignal(self, "tagRemoved:" .. tag)
		end,
	},
})
def("ContentProvider", {
	base = "Instance",
	service = true,
	ro = { RequestQueueSize = true },
	defaults = { RequestQueueSize = 0 },
	methods = {
		PreloadAsync = function(_, list, callback)
			assert(type(list) == "table", "PreloadAsync expects an array")
			if canYield() then
				task.wait()
			end
			if callback then
				for _, c in ipairs(list) do
					callback(type(c) == "string" and c or "", Enum.AssetFetchStatus.Success)
				end
			end
		end,
	},
})
def("HttpService", {
	base = "Instance",
	service = true,
	methods = {
		GenerateGUID = function(_, braces)
			local n = MOCK.__guid or 0
			MOCK.__guid = n + 1
			local s = string.format("%08X-0000-4000-8000-%012X", n, n)
			if braces == false then
				return s
			end
			return "{" .. s .. "}"
		end,
	},
})

---------------------------------------------------------------- Simulation helpers
local services = {} -- filled at the end
local gameObj, workspaceObj, terrain

local function isSimulated(o)
	-- in the Workspace or inside a WorldModel (ViewportFrames without a WorldModel don't simulate)
	local a = parentOf(o)
	while a do
		if a == workspaceObj then
			return true
		end
		if rawget(a, "__class") == "WorldModel" then
			return true
		end
		a = parentOf(a)
	end
	return false
end
MOCK.isSimulated = isSimulated

---------------------------------------------------------------- Raycasting
local RP = {}
TYPE_NAMES[RP] = "RaycastParams"
local RP_TYPES = {
	FilterType = "Enum:RaycastFilterType",
	FilterDescendantsInstances = "list",
	IgnoreWater = "boolean",
	CollisionGroup = "string",
	RespectCanCollide = "boolean",
	BruteForceAllSlow = "boolean",
}
local OP = {}
TYPE_NAMES[OP] = "OverlapParams"
local OP_TYPES = {
	FilterType = "Enum:RaycastFilterType",
	FilterDescendantsInstances = "list",
	MaxParts = "int",
	CollisionGroup = "string",
	RespectCanCollide = "boolean",
	BruteForceAllSlow = "boolean",
}
local function paramsClass(mt, typeName, types, defaults)
	mt.__index = function(p, k)
		local d = rawget(p, "__d")
		if types[k] then
			local v = d[k]
			if k == "FilterDescendantsInstances" then
				return table.clone(v)
			end
			return v
		elseif k == "AddToFilter" then
			return function(self, x)
				local list = rawget(self, "__d").FilterDescendantsInstances
				if isInstance(x) then
					table.insert(list, x)
				else
					for _, i in ipairs(x) do
						assert(isInstance(i), typeName .. ":AddToFilter expects Instances")
						table.insert(list, i)
					end
				end
			end
		end
		error(typeName .. " has no member " .. tostring(k), 2)
	end
	mt.__newindex = function(p, k, v)
		local t = types[k]
		if not t then
			error(typeName .. " has no property " .. tostring(k), 2)
		end
		if t == "list" then
			if type(v) ~= "table" then
				error("Unable to cast value to Objects", 2)
			end
			for _, i in ipairs(v) do
				if not isInstance(i) then
					error("Unable to cast value to Objects (" .. typeName .. ".FilterDescendantsInstances needs Instances)", 2)
				end
			end
			v = table.clone(v)
		else
			local ok, cv = checkerFor(t)(v)
			if not ok then
				error("invalid value for " .. typeName .. "." .. k .. " (" .. tostring(cv) .. " expected, got " .. typeof(v) .. ")", 2)
			end
			v = cv
		end
		rawget(p, "__d")[k] = v
	end
	return function(init)
		local p = setmetatable({ __d = table.clone(defaults) }, mt)
		rawget(p, "__d").FilterDescendantsInstances = {}
		if init then
			for k, v in pairs(init) do
				p[k] = v
			end
		end
		return p
	end
end
RaycastParams = {
	new = paramsClass(RP, "RaycastParams", RP_TYPES, {
		FilterType = Enum.RaycastFilterType.Exclude,
		IgnoreWater = false,
		CollisionGroup = "Default",
		RespectCanCollide = false,
		BruteForceAllSlow = false,
	}),
}
OverlapParams = {
	new = paramsClass(OP, "OverlapParams", OP_TYPES, {
		FilterType = Enum.RaycastFilterType.Exclude,
		MaxParts = 0,
		CollisionGroup = "Default",
		RespectCanCollide = false,
		BruteForceAllSlow = false,
	}),
}
local RR = {}
TYPE_NAMES[RR] = "RaycastResult"
RR.__index = strictIndex("RaycastResult", {})
RR.__newindex = immutable("RaycastResult")
function MOCK.raycastResult(inst, pos, normal, material, distance)
	return setmetatable({ Instance = inst, Position = pos, Normal = normal, Material = material, Distance = distance }, RR)
end

local function filterAllows(params, inst)
	if not params then
		return true
	end
	local d = rawget(params, "__d")
	local inList = false
	for _, f in ipairs(d.FilterDescendantsInstances) do
		if inst == f or Inst.IsDescendantOf(inst, f) then
			inList = true
			break
		end
	end
	local ft = d.FilterType.Name
	if ft == "Include" or ft == "Whitelist" then
		return inList
	end
	return not inList
end
MOCK.filterAllows = filterAllows

local function rayBox(cf, size, origin, dir)
	local o = cf:PointToObjectSpace(origin)
	local d = cf:VectorToObjectSpace(dir)
	local h = size / 2
	local tmin, tmax = -math.huge, math.huge
	local axis, sign = 0, 1
	local comps = { { o.X, d.X, h.X }, { o.Y, d.Y, h.Y }, { o.Z, d.Z, h.Z } }
	for i, c in ipairs(comps) do
		local oc, dc, hc = c[1], c[2], c[3]
		if math.abs(dc) < 1e-12 then
			if math.abs(oc) > hc then
				return nil
			end
		else
			local t1, t2 = (-hc - oc) / dc, (hc - oc) / dc
			local s = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				s = 1
			end
			if t1 > tmin then
				tmin, axis, sign = t1, i, s
			end
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	if tmin < 0 or tmin > 1 or axis == 0 then
		return nil -- starting inside a part never hits it (like Roblox)
	end
	local n = (axis == 1 and Vector3.xAxis) or (axis == 2 and Vector3.yAxis) or Vector3.zAxis
	return tmin, cf:VectorToWorldSpace(n * sign)
end

local function raycast(root, origin, dir, params)
	if not isV3(origin) or not isV3(dir) then
		error("Raycast(origin: Vector3, direction: Vector3, params: RaycastParams?)", 3)
	end
	if params ~= nil and getmetatable(params) ~= RP then
		error("Unable to cast value to RaycastParams", 3)
	end
	if dir.Magnitude > 15000 then
		mockWarn("Raycast direction longer than 15000 studs gets truncated")
		dir = dir.Unit * 15000
	end
	MOCK.raycasts += 1
	if MOCK.raycastHook then
		local r = MOCK.raycastHook(origin, dir, params)
		if r ~= nil then
			return r or nil
		end
	end
	local best, bestT, bestN = nil, math.huge, nil
	local respect = params and rawget(params, "__d").RespectCanCollide
	for _, p in ipairs(Inst.GetDescendants(root)) do
		if isPart(p) then
			local props = rawget(p, "__props")
			local cc = p.CanCollide
			if (respect and cc) or (not respect and (cc or p.CanQuery)) then
				if filterAllows(params, p) then
					local t, n = rayBox(props.CFrame, props.Size, origin, dir)
					if t and t < bestT then
						best, bestT, bestN = p, t, n
					end
				end
			end
		end
	end
	local gy = MOCK.groundY
	if root == workspaceObj and gy and dir.Y < 0 and origin.Y >= gy and filterAllows(params, terrain) then
		local t = (gy - origin.Y) / dir.Y
		if t >= 0 and t <= 1 and t < bestT then
			best, bestT, bestN = terrain, t, Vector3.yAxis
		end
	end
	if not best then
		return nil
	end
	local pos = origin + dir * bestT
	local mat = best == terrain and Enum.Material.Grass or best.Material
	return MOCK.raycastResult(best, pos, bestN, mat, (dir * bestT).Magnitude)
end
local function partsInRadius(root, pos, r, params)
	local out = {}
	for _, p in ipairs(Inst.GetDescendants(root)) do
		if isPart(p) and p.CanQuery and (params == nil or filterAllows(params, p)) then
			local half = p.Size.Magnitude / 2
			if (p.Position - pos).Magnitude <= r + half then
				table.insert(out, p)
			end
		end
	end
	return out
end
local worldMethods = {
	Raycast = function(self, origin, dir, params)
		return raycast(self, origin, dir, params)
	end,
	GetPartBoundsInRadius = function(self, pos, r, params)
		assert(isV3(pos) and type(r) == "number", "GetPartBoundsInRadius(Vector3, number, OverlapParams?)")
		return partsInRadius(self, pos, r, params)
	end,
	GetPartBoundsInBox = function(self, cf, size, params)
		assert(isCF(cf) and isV3(size), "GetPartBoundsInBox(CFrame, Vector3, OverlapParams?)")
		return partsInRadius(self, cf.Position, size.Magnitude / 2, params)
	end,
	GetPartsInPart = function()
		return {}
	end,
}
for k, f in pairs(worldMethods) do
	RAW_DEFS.Workspace.methods[k] = f
end
RAW_DEFS.WorldModel.methods = table.clone(worldMethods)
RAW_DEFS.Workspace.methods.BulkMoveTo = function(_, parts, cframes, mode)
	if type(parts) ~= "table" or type(cframes) ~= "table" then
		error("BulkMoveTo(partList, cframeList, eventMode?)", 2)
	end
	if #parts ~= #cframes then
		error("BulkMoveTo: partList and cframeList must have the same length", 2)
	end
	if mode ~= nil and not isEnum(mode, "BulkMoveMode") then
		error("BulkMoveTo: eventMode must be Enum.BulkMoveMode", 2)
	end
	for i, p in ipairs(parts) do
		local cf = cframes[i]
		if not (isInstance(p) and isPart(p)) then
			error("BulkMoveTo: partList[" .. i .. "] is not a BasePart", 2)
		end
		if not isCF(cf) then
			error("BulkMoveTo: cframeList[" .. i .. "] is not a CFrame", 2)
		end
		local props = rawget(p, "__props")
		local old = props.CFrame
		props.CFrame = cf
		props.Position = cf.Position
		if rawget(p, "__sig") and old ~= cf then
			changed(p, "CFrame", cf)
		end
	end
end
RAW_DEFS.WorldModel.methods.BulkMoveTo = RAW_DEFS.Workspace.methods.BulkMoveTo
RAW_DEFS.Workspace.methods.GetServerTimeNow = function()
	return tick()
end
RAW_DEFS.Workspace.methods.GetRealPhysicsFPS = function()
	return 60
end
RAW_DEFS.Workspace.methods.GetNumAwakeParts = function()
	return 0
end
RAW_DEFS.Workspace.set = {
	StreamingEnabled = editOnly,
	StreamingMinRadius = editOnly,
	StreamingTargetRadius = editOnly,
	StreamingIntegrityMode = editOnly,
	StreamOutBehavior = editOnly,
	CurrentCamera = function(o, v)
		internal(o).camera = v
		changed(o, "CurrentCamera", v)
	end,
}
RAW_DEFS.Workspace.get = {
	DistributedGameTime = RAW_DEFS.Workspace.get.DistributedGameTime,
	CurrentCamera = function(o)
		local int = internal(o)
		local cam = int.camera
		if cam == nil or rawget(cam, "__destroyed") then
			cam = makeInstance(resolve("Camera"))
			cam.Name = "Camera"
			cam.Parent = o
			int.camera = cam
		end
		return cam
	end,
}

---------------------------------------------------------------- DataModel
RAW_DEFS.DataModel.methods = {
	GetService = function(_, name)
		local s = services[name]
		if not s then
			error("Mock: unknown service " .. tostring(name))
		end
		return s
	end,
	FindService = function(_, name)
		return services[name]
	end,
	IsLoaded = function()
		return true
	end,
	BindToClose = function(_, fn)
		assert(type(fn) == "function", "BindToClose expects a function")
		MOCK.closeCallbacks = MOCK.closeCallbacks or {}
		table.insert(MOCK.closeCallbacks, fn)
	end,
}
RAW_DEFS.ChangeHistoryService.methods = {
	SetWaypoint = function() end,
	TryBeginRecording = function()
		return "mock"
	end,
	FinishRecording = function() end,
}

---------------------------------------------------------------- RunService
local renderBindings = {}
local bindSeq = 0
RAW_DEFS.RunService.methods = {
	IsStudio = function()
		return MOCK.studio
	end,
	IsClient = function()
		return curCtx ~= "server"
	end,
	IsServer = function()
		return curCtx ~= "client"
	end,
	IsRunning = function()
		return MOCK.running
	end,
	IsRunMode = function()
		return false
	end,
	IsEdit = function()
		return not MOCK.running
	end,
	BindToRenderStep = function(_, name, priority, fn)
		if curCtx == "server" then
			error("BindToRenderStep can only be used from the client", 2)
		end
		if type(name) ~= "string" then
			error("BindToRenderStep: name must be a string", 2)
		end
		if type(priority) ~= "number" then
			error("BindToRenderStep: priority must be a number (use Enum.RenderPriority.X.Value)", 2)
		end
		if type(fn) ~= "function" then
			error("BindToRenderStep: function expected", 2)
		end
		bindSeq += 1
		table.insert(renderBindings, { name = name, priority = priority, fn = fn, ctx = curCtx, seq = bindSeq })
		table.sort(renderBindings, function(a, b)
			if a.priority ~= b.priority then
				return a.priority < b.priority
			end
			return a.seq < b.seq
		end)
	end,
	UnbindFromRenderStep = function(_, name)
		for i = #renderBindings, 1, -1 do
			if renderBindings[i].name == name then
				table.remove(renderBindings, i)
			end
		end
	end,
	Set3dRenderingEnabled = function(_, on)
		if curCtx == "server" then
			error("Set3dRenderingEnabled can only be used from the client", 2)
		end
		assert(type(on) == "boolean", "Set3dRenderingEnabled expects a boolean")
		MOCK.rendering3d = on
	end,
}
function MOCK.renderBindings()
	local out = {}
	for _, b in ipairs(renderBindings) do
		table.insert(out, b.name .. "@" .. b.priority)
	end
	return out
end

---------------------------------------------------------------- TweenService
local EASE = {
	Linear = function(t)
		return t
	end,
	Sine = function(t)
		return 1 - math.cos(t * math.pi / 2)
	end,
	Quad = function(t)
		return t * t
	end,
	Cubic = function(t)
		return t * t * t
	end,
	Quart = function(t)
		return t ^ 4
	end,
	Quint = function(t)
		return t ^ 5
	end,
	Exponential = function(t)
		return t <= 0 and 0 or 2 ^ (10 * t - 10)
	end,
	Circular = function(t)
		return 1 - math.sqrt(math.max(1 - t * t, 0))
	end,
	Back = function(t)
		local c1 = 1.70158
		return (c1 + 1) * t * t * t - c1 * t * t
	end,
	Elastic = function(t)
		if t <= 0 then
			return 0
		elseif t >= 1 then
			return 1
		end
		return -(2 ^ (10 * t - 10)) * math.sin((10 * t - 10.75) * (2 * math.pi / 3))
	end,
}
local function bounceOut(t)
	local n1, d1 = 7.5625, 2.75
	if t < 1 / d1 then
		return n1 * t * t
	elseif t < 2 / d1 then
		t -= 1.5 / d1
		return n1 * t * t + 0.75
	elseif t < 2.5 / d1 then
		t -= 2.25 / d1
		return n1 * t * t + 0.9375
	end
	t -= 2.625 / d1
	return n1 * t * t + 0.984375
end
EASE.Bounce = function(t)
	return 1 - bounceOut(1 - t)
end
local function ease(style, dir, t)
	local f = EASE[style.Name]
	local d = dir.Name
	if d == "In" then
		return f(t)
	elseif d == "Out" then
		return 1 - f(1 - t)
	end
	if t < 0.5 then
		return f(2 * t) / 2
	end
	return 1 - f(2 - 2 * t) / 2
end
MOCK.ease = ease
local function lerpValue(a, b, t)
	local ta = typeof(a)
	if ta == "number" then
		return a + (b - a) * t
	elseif ta == "Color3" or ta == "Vector3" or ta == "Vector2" or ta == "CFrame" or ta == "UDim2" then
		return a:Lerp(b, t)
	elseif ta == "UDim" then
		return UDim.new(a.Scale + (b.Scale - a.Scale) * t, a.Offset + (b.Offset - a.Offset) * t)
	elseif ta == "Rect" then
		return Rect.new(a.Min:Lerp(b.Min, t), a.Max:Lerp(b.Max, t))
	end
	return t >= 1 and b or a
end
MOCK.lerpValue = lerpValue
local TWEENABLE = { number = true, boolean = true, CFrame = true, Rect = true, Color3 = true, UDim = true, UDim2 = true, Vector2 = true, Vector3 = true, EnumItem = true }
local activeTweens = {}
local function tweenFinish(tw, state)
	local ti = internal(tw)
	ti.state = state
	for i, x in ipairs(activeTweens) do
		if x == tw then
			table.remove(activeTweens, i)
			break
		end
	end
	fireIf(tw, "Completed", state)
end
local function tweenBegin(tw)
	local ti = internal(tw)
	ti.state = Enum.PlaybackState.Playing
	ti.start = {}
	for k in pairs(ti.goals) do
		ti.start[k] = ti.inst[k]
	end
	-- a newer tween on the same property cancels the older one
	for _, other in ipairs(table.clone(activeTweens)) do
		local oi = internal(other)
		if other ~= tw and oi.inst == ti.inst and oi.state == Enum.PlaybackState.Playing then
			for k in pairs(ti.goals) do
				if oi.goals[k] ~= nil then
					tweenFinish(other, Enum.PlaybackState.Cancelled)
					break
				end
			end
		end
	end
end
local function tweenApply(tw)
	local ti = internal(tw)
	local info = ti.info
	local T = info.Time
	local cycle = T * (info.Reverses and 2 or 1)
	local done, alpha = false, 1
	if cycle <= 0 then
		done = true
	else
		local n = math.floor(ti.elapsed / cycle)
		if info.RepeatCount >= 0 and n > info.RepeatCount then
			done = true
		else
			local tc = ti.elapsed - n * cycle
			alpha = tc <= T and tc / T or 2 - tc / T
		end
	end
	if done then
		for k, goal in pairs(ti.goals) do
			ti.inst[k] = info.Reverses and ti.start[k] or goal
		end
		tweenFinish(tw, Enum.PlaybackState.Completed)
		return
	end
	local e = ease(info.EasingStyle, info.EasingDirection, alpha)
	for k, goal in pairs(ti.goals) do
		ti.inst[k] = lerpValue(ti.start[k], goal, e)
	end
end
local function stepTweens(dt)
	for _, tw in ipairs(table.clone(activeTweens)) do
		local ti = internal(tw)
		local st = ti.state
		if st == Enum.PlaybackState.Playing or st == Enum.PlaybackState.Delayed then
			ti.elapsed += dt
			if st == Enum.PlaybackState.Delayed then
				if ti.elapsed >= ti.info.DelayTime then
					ti.elapsed -= ti.info.DelayTime
					tweenBegin(tw)
				end
			end
			if ti.state == Enum.PlaybackState.Playing then
				tweenApply(tw)
			end
		end
	end
end
MOCK.activeTweenCount = function()
	return #activeTweens
end
RAW_DEFS.Tween.get = {
	Instance = function(o)
		return internal(o).inst
	end,
	TweenInfo = function(o)
		return internal(o).info
	end,
	PlaybackState = function(o)
		return internal(o).state
	end,
}
RAW_DEFS.Tween.methods = {
	Play = function(tw)
		local ti = internal(tw)
		local st = ti.state
		if st == Enum.PlaybackState.Playing or st == Enum.PlaybackState.Delayed then
			return
		end
		if st == Enum.PlaybackState.Paused then
			ti.state = ti.start and Enum.PlaybackState.Playing or Enum.PlaybackState.Delayed
		else
			ti.elapsed = 0
			ti.start = nil
			if ti.info.DelayTime > 0 then
				ti.state = Enum.PlaybackState.Delayed
			else
				tweenBegin(tw)
			end
		end
		table.insert(activeTweens, tw)
	end,
	Pause = function(tw)
		local ti = internal(tw)
		if ti.state == Enum.PlaybackState.Playing or ti.state == Enum.PlaybackState.Delayed then
			ti.state = Enum.PlaybackState.Paused
			for i, x in ipairs(activeTweens) do
				if x == tw then
					table.remove(activeTweens, i)
					break
				end
			end
		end
	end,
	Cancel = function(tw)
		local ti = internal(tw)
		local st = ti.state
		ti.elapsed = 0
		if st == Enum.PlaybackState.Playing or st == Enum.PlaybackState.Delayed or st == Enum.PlaybackState.Paused then
			local wasActive = st ~= Enum.PlaybackState.Paused
			if wasActive then
				tweenFinish(tw, Enum.PlaybackState.Cancelled)
			else
				ti.state = Enum.PlaybackState.Cancelled
				fireIf(tw, "Completed", Enum.PlaybackState.Cancelled)
			end
		end
	end,
}
RAW_DEFS.TweenService.methods = {
	Create = function(_, inst, info, goals)
		if not isInstance(inst) then
			error("TweenService:Create: argument 1 must be an Instance", 2)
		end
		if typeof(info) ~= "TweenInfo" then
			error("TweenService:Create: argument 2 must be a TweenInfo", 2)
		end
		if type(goals) ~= "table" then
			error("TweenService:Create: argument 3 must be a table of property goals", 2)
		end
		local c = defOf(inst)
		local g = {}
		for k, v in pairs(goals) do
			if type(k) ~= "string" or (c.props[k] == nil and not c.permissive) then
				error("TweenService:Create no property named '" .. tostring(k) .. "' for object '" .. tostring(inst.Name) .. "'", 2)
			end
			local cur = inst[k]
			if cur == nil then
				error("Mock: no default value known for " .. c.name .. "." .. k .. " (add one to the mock)", 2)
			end
			local tc, tv = typeof(cur), typeof(v)
			if not TWEENABLE[tv] or tc ~= tv or (tv == "EnumItem" and rawget(cur, "__t") ~= rawget(v, "__t")) then
				error("TweenService:Create property named '" .. k .. "' cannot be tweened due to type mismatch (property is a '" .. tc .. "', but given type is '" .. tv .. "')", 2)
			end
			local chk = c.props[k]
			if chk ~= true and chk ~= nil then
				local ok = chk(v)
				if not ok then
					error("TweenService:Create: invalid goal for " .. k, 2)
				end
			end
			g[k] = v
		end
		local tw = makeInstance(resolve("Tween"))
		local ti = internal(tw)
		ti.inst, ti.info, ti.goals = inst, info, g
		ti.state = Enum.PlaybackState.Begin
		ti.elapsed = 0
		return tw
	end,
	GetValue = function(_, alpha, style, dir)
		assert(type(alpha) == "number" and isEnum(style, "EasingStyle") and isEnum(dir, "EasingDirection"), "TweenService:GetValue(number, EasingStyle, EasingDirection)")
		return ease(style, dir, math.clamp(alpha, 0, 1))
	end,
}

---------------------------------------------------------------- Input
local keysDown = {}
local casActions = {} -- name -> action
local casSeq = 0
local function newInput(kc, state)
	local io = makeInstance(resolve("InputObject"))
	local p = rawget(io, "__props")
	p.KeyCode = kc
	p.UserInputType = Enum.UserInputType.Keyboard
	p.UserInputState = state
	return io
end
local function casDispatch(kc, state, io)
	local list = {}
	for _, a in pairs(casActions) do
		for _, inp in ipairs(a.inputs) do
			if inp == kc or inp == Enum.UserInputType.Keyboard then
				table.insert(list, a)
				break
			end
		end
	end
	table.sort(list, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.seq > b.seq
	end)
	for _, a in ipairs(list) do
		local prev = curCtx
		curCtx = a.ctx
		local ok, res = pcall(a.fn, a.name, state, io)
		curCtx = prev
		if not ok then
			reportError(res)
			return true
		end
		if res ~= Enum.ContextActionResult.Pass then
			return true
		end
	end
	return false
end
-- Simulates a key press (fires ContextActionService actions and UserInputService.InputBegan now).
function MOCK.pressKey(kc, gameProcessed)
	assert(isEnum(kc, "KeyCode"), "MOCK.pressKey expects Enum.KeyCode")
	keysDown[kc] = true
	local io = newInput(kc, Enum.UserInputState.Begin)
	local sunk = casDispatch(kc, Enum.UserInputState.Begin, io)
	fire(getSignal(services.UserInputService, "InputBegan"), io, gameProcessed or false)
	return sunk
end
function MOCK.releaseKey(kc, gameProcessed)
	keysDown[kc] = nil
	local io = newInput(kc, Enum.UserInputState.End)
	casDispatch(kc, Enum.UserInputState.End, io)
	fire(getSignal(services.UserInputService, "InputEnded"), io, gameProcessed or false)
end
function MOCK.tapKey(kc, gameProcessed)
	MOCK.pressKey(kc, gameProcessed)
	MOCK.releaseKey(kc, gameProcessed)
end
RAW_DEFS.UserInputService.methods = {
	IsKeyDown = function(_, kc)
		return keysDown[kc] == true
	end,
	IsMouseButtonPressed = function()
		return false
	end,
	GetKeysPressed = function()
		local out = {}
		for kc in pairs(keysDown) do
			table.insert(out, newInput(kc, Enum.UserInputState.Begin))
		end
		return out
	end,
	GetMouseLocation = function()
		return MOCK.viewportSize / 2
	end,
	GetMouseDelta = function()
		return Vector2.zero
	end,
	GetFocusedTextBox = function()
		return nil
	end,
	GetLastInputType = function()
		return Enum.UserInputType.Keyboard
	end,
	GetConnectedGamepads = function()
		return {}
	end,
	GetNavigationGamepads = function()
		return {}
	end,
	GetGamepadConnected = function()
		return false
	end,
	GetStringForKeyCode = function(_, kc)
		return kc.Name
	end,
	GetImageForKeyCode = function()
		return ""
	end,
}
local function casBind(name, fn, priority, ...)
	if curCtx == "server" then
		error("ContextActionService can only be used from the client", 3)
	end
	if type(name) ~= "string" then
		error("BindAction: action name must be a string", 3)
	end
	if type(fn) ~= "function" then
		error("BindAction: function expected", 3)
	end
	local inputs = { ... }
	for i, inp in ipairs(inputs) do
		if not (isEnum(inp, "KeyCode") or isEnum(inp, "UserInputType")) then
			error("BindAction: input " .. i .. " must be Enum.KeyCode or Enum.UserInputType", 3)
		end
	end
	casSeq += 1
	casActions[name] = { name = name, fn = fn, priority = priority, inputs = inputs, seq = casSeq, ctx = curCtx }
end
RAW_DEFS.ContextActionService.methods = {
	BindAction = function(_, name, fn, touch, ...)
		casBind(name, fn, Enum.ContextActionPriority.Default.Value, ...)
	end,
	BindActionAtPriority = function(_, name, fn, touch, priority, ...)
		if type(priority) ~= "number" then
			error("BindActionAtPriority: priority must be a number", 2)
		end
		casBind(name, fn, priority, ...)
	end,
	UnbindAction = function(_, name)
		casActions[name] = nil
	end,
	UnbindAllActions = function()
		casActions = {}
	end,
	GetBoundActionInfo = function(_, name)
		local a = casActions[name]
		if not a then
			return {}
		end
		return { inputTypes = table.clone(a.inputs), priorityLevel = a.priority, stackOrder = a.seq }
	end,
	GetAllBoundActionInfo = function()
		local out = {}
		for n, a in pairs(casActions) do
			out[n] = { inputTypes = table.clone(a.inputs), priorityLevel = a.priority, stackOrder = a.seq }
		end
		return out
	end,
	SetTitle = function() end,
	SetDescription = function() end,
	SetImage = function() end,
	SetPosition = function() end,
	GetButton = function()
		return nil
	end,
}
function MOCK.boundActions()
	local out = {}
	for n in pairs(casActions) do
		table.insert(out, n)
	end
	table.sort(out)
	return out
end

---------------------------------------------------------------- StarterGui (core GUI)
MOCK.coreGui = { PlayerList = true, Health = true, Backpack = true, Chat = true, EmotesMenu = true, SelfView = true, Captures = true }
MOCK.core = { ResetButtonCallback = true, TopbarEnabled = true, ChatActive = true, PointsNotificationsActive = true, BadgesNotificationsActive = true, AvatarContextMenuEnabled = false }
local CORE_SET_ONLY = { SendNotification = true, ChatMakeSystemMessage = true, PromptSendFriendRequest = true, PromptBlockPlayer = true, PromptUnblockPlayer = true, DevConsoleVisible = true, CoreGuiChatConnections = true }
RAW_DEFS.StarterGui.methods = {
	SetCoreGuiEnabled = function(_, t, on)
		if curCtx == "server" then
			error("SetCoreGuiEnabled can only be called from a LocalScript", 2)
		end
		assert(isEnum(t, "CoreGuiType"), "SetCoreGuiEnabled: Enum.CoreGuiType expected")
		assert(type(on) == "boolean", "SetCoreGuiEnabled: boolean expected")
		if t.Name == "All" then
			for k in pairs(MOCK.coreGui) do
				MOCK.coreGui[k] = on
			end
		else
			MOCK.coreGui[t.Name] = on
		end
	end,
	GetCoreGuiEnabled = function(_, t)
		assert(isEnum(t, "CoreGuiType"), "GetCoreGuiEnabled: Enum.CoreGuiType expected")
		if t.Name == "All" then
			for _, v in pairs(MOCK.coreGui) do
				if not v then
					return false
				end
			end
			return true
		end
		return MOCK.coreGui[t.Name]
	end,
	SetCore = function(_, name, value)
		if curCtx == "server" then
			error("SetCore can only be called from a LocalScript", 2)
		end
		if MOCK.core[name] == nil and not CORE_SET_ONLY[name] then
			error("SetCore: " .. tostring(name) .. " has not been registered by the CoreScripts", 2)
		end
		if not CORE_SET_ONLY[name] then
			MOCK.core[name] = value
		end
	end,
	GetCore = function(_, name)
		if MOCK.core[name] == nil then
			error("GetCore: " .. tostring(name) .. " has not been registered by the CoreScripts", 2)
		end
		return MOCK.core[name]
	end,
}

---------------------------------------------------------------- Animator
local function rigModelOf(animator)
	local p = parentOf(animator)
	return p and parentOf(p)
end
local function newTrack(animator, anim)
	local tr = makeInstance(resolve("AnimationTrack"))
	local ti = internal(tr)
	ti.animator = animator
	ti.animation = anim
	ti.time = 0
	ti.speed = 1
	ti.weight = 0
	ti.weightTarget = 1
	ti.fade = 0.1
	ti.playing = false
	local id = anim.AnimationId
	ti.length = id == "" and 0 or (MOCK.animationLengths and MOCK.animationLengths[id] or 1)
	rawget(tr, "__props").Name = anim.Name
	return tr
end
local function animatorLoad(animator, anim)
	if not (isInstance(anim) and anim:IsA("Animation")) then
		error("LoadAnimation requires an Animation object", 3)
	end
	if not Inst.IsDescendantOf(animator, gameObj) then
		error("LoadAnimation requires the Animator object (" .. tostring(animator.Name) .. ") to be a descendant of the game object", 3)
	end
	return newTrack(animator, anim)
end
local function playingTracks(animator)
	local out = {}
	local int = rawget(animator, "__int")
	for _, tr in ipairs(int and int.tracks or {}) do
		if internal(tr).playing then
			table.insert(out, tr)
		end
	end
	return out
end
RAW_DEFS.Animator.methods = {
	LoadAnimation = function(self, anim)
		return animatorLoad(self, anim)
	end,
	GetPlayingAnimationTracks = function(self)
		return playingTracks(self)
	end,
	ApplyJointVelocities = function() end,
}
local function ensureAnimator(parent)
	local a = Inst.FindFirstChildOfClass(parent, "Animator")
	if not a then
		a = makeInstance(resolve("Animator"))
		a.Parent = parent
	end
	return a
end
RAW_DEFS.AnimationController.methods = {
	LoadAnimation = function(self, anim)
		return animatorLoad(ensureAnimator(self), anim)
	end,
	GetPlayingAnimationTracks = function(self)
		return playingTracks(ensureAnimator(self))
	end,
}
RAW_DEFS.AnimationTrack.get = {
	IsPlaying = function(o)
		return internal(o).playing
	end,
	Length = function(o)
		return internal(o).length
	end,
	Speed = function(o)
		return internal(o).speed
	end,
	WeightCurrent = function(o)
		return internal(o).weight
	end,
	WeightTarget = function(o)
		return internal(o).weightTarget
	end,
	Animation = function(o)
		return internal(o).animation
	end,
	TimePosition = function(o)
		return internal(o).time
	end,
}
RAW_DEFS.AnimationTrack.set = {
	TimePosition = function(o, v)
		internal(o).time = v
	end,
}
RAW_DEFS.AnimationTrack.methods = {
	Play = function(tr, fade, weight, speed)
		local ti = internal(tr)
		ti.fade = fade or 0.1
		ti.weightTarget = weight or 1
		ti.speed = speed or 1
		ti.stopping = false
		if not ti.playing then
			ti.playing = true
			local aint = internal(ti.animator)
			aint.tracks = aint.tracks or {}
			if not table.find(aint.tracks, tr) then
				table.insert(aint.tracks, tr)
			end
			fireIf(ti.animator, "AnimationPlayed", tr)
		end
	end,
	Stop = function(tr, fade)
		local ti = internal(tr)
		if ti.playing then
			ti.playing = false
			ti.stopping = true
			ti.fade = fade or 0.1
			fireIf(tr, "Stopped")
		end
	end,
	AdjustSpeed = function(tr, s)
		internal(tr).speed = s or 1
	end,
	AdjustWeight = function(tr, w, fade)
		local ti = internal(tr)
		ti.weightTarget = w or 1
		ti.fade = fade or 0.1
	end,
	GetMarkerReachedSignal = function(tr, name)
		return getSignal(tr, "marker:" .. tostring(name))
	end,
	GetTimeOfKeyframe = function()
		return 0
	end,
}
local function motorsOf(model)
	local out = {}
	for _, d in ipairs(Inst.GetDescendants(model)) do
		if rawget(d, "__class") == "Motor6D" then
			table.insert(out, d)
		end
	end
	return out
end
local function stepAnimators(dt)
	local alive = {}
	for _, a in ipairs(MOCK._animators) do
		if not rawget(a, "__destroyed") then
			table.insert(alive, a)
			local int = rawget(a, "__int")
			local tracks = int and int.tracks
			if tracks and (#tracks > 0 or int.dirty) and isSimulated(a) then
				local weight = 0
				local phase = 0
				for _, tr in ipairs(table.clone(tracks)) do
					local ti = internal(tr)
					local target = ti.playing and ti.weightTarget or 0
					if ti.fade <= 0 then
						ti.weight = target
					elseif ti.weight < target then
						ti.weight = math.min(target, ti.weight + dt / ti.fade)
					elseif ti.weight > target then
						ti.weight = math.max(target, ti.weight - dt / ti.fade)
					end
					ti.time += dt * ti.speed
					if ti.length > 0 and ti.time >= ti.length then
						if tr.Looped then
							ti.time = ti.time % ti.length
							fireIf(tr, "DidLoop")
						else
							ti.time = ti.length
							if ti.playing then
								ti.playing = false
								ti.stopping = true
								fireIf(tr, "Stopped")
							end
						end
					end
					if not ti.playing and ti.weight <= 0 then
						table.remove(tracks, table.find(tracks, tr))
						if ti.stopping then
							ti.stopping = false
							fireIf(tr, "Ended")
						end
					end
					if ti.weight > weight then
						weight = ti.weight
						phase = ti.length > 0 and ti.time / ti.length or 0
					end
				end
				local model = rigModelOf(a)
				if model and (weight > 0 or int.dirty) then
					-- the mock "animation": a small sway on every joint, scaled by the track weight
					for i, m in ipairs(motorsOf(model)) do
						local ang = 0.08 * weight * math.sin(2 * math.pi * phase + i)
						rawget(m, "__props").Transform = CFrame.Angles(ang, 0, ang * 0.5)
						local mi = internal(m)
						mi.writer = "animator"
						mi.writeFrame = MOCK.frame
					end
					MOCK.animatorWrites = (MOCK.animatorWrites or 0) + 1
				end
				int.dirty = weight > 0
			end
		end
	end
	MOCK._animators = alive
end

---------------------------------------------------------------- Humanoid
local function setState(h, st)
	local int = internal(h)
	local old = int.state or Enum.HumanoidStateType.Running
	if int.disabledStates and int.disabledStates[st] then
		return
	end
	int.state = st
	if old ~= st then
		fireIf(h, "StateChanged", old, st)
		if st == Enum.HumanoidStateType.PlatformStanding then
			fireIf(h, "PlatformStanding")
		end
	end
end
local function charOf(h)
	return parentOf(h)
end
local function rightHand(char)
	return Inst.FindFirstChild(char, "RightHand") or Inst.FindFirstChild(char, "Right Arm")
end
local function equipTool(tool, char)
	local hand = rightHand(char)
	local handle = Inst.FindFirstChild(tool, "Handle")
	if hand and handle and tool.RequiresHandle ~= false then
		local old = Inst.FindFirstChild(hand, "RightGrip")
		if old then
			old:Destroy()
		end
		local w = makeInstance(resolve("Weld"))
		w.Name = "RightGrip"
		w.Part0 = hand
		w.Part1 = handle
		local att = Inst.FindFirstChild(hand, "RightGripAttachment")
		w.C0 = att and att.CFrame or CFrame.new(0, -1, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0)
		w.C1 = tool.Grip
		w.Parent = hand
	end
	fireIf(tool, "Equipped")
end
function MOCK.__toolParented(tool, new, old)
	if old and Inst.FindFirstChildOfClass(old, "Humanoid") then
		local hand = rightHand(old)
		local grip = hand and Inst.FindFirstChild(hand, "RightGrip")
		if grip and grip.Part1 and Inst.IsDescendantOf(grip.Part1, tool) then
			grip:Destroy()
		end
		fireIf(tool, "Unequipped")
	end
	if new and Inst.FindFirstChildOfClass(new, "Humanoid") then
		equipTool(tool, new)
	end
end
local hum = RAW_DEFS.Humanoid
hum.set.PlatformStand = function(o, v)
	store(o, "PlatformStand", v)
	if v then
		setState(o, Enum.HumanoidStateType.PlatformStanding)
	elseif internal(o).state == Enum.HumanoidStateType.PlatformStanding then
		setState(o, Enum.HumanoidStateType.Running)
	end
end
hum.set.Health = function(o, v)
	v = math.clamp(v, 0, o.MaxHealth)
	local old = o.Health
	store(o, "Health", v)
	if v ~= old then
		fireIf(o, "HealthChanged", v)
	end
	if v <= 0 and old > 0 then
		setState(o, Enum.HumanoidStateType.Dead)
		fireIf(o, "Died")
	end
end
hum.methods.GetState = function(o)
	return internal(o).state or Enum.HumanoidStateType.Running
end
hum.methods.ChangeState = function(o, st)
	if not isEnum(st, "HumanoidStateType") then
		error("ChangeState: Enum.HumanoidStateType expected", 2)
	end
	setState(o, st)
end
hum.methods.SetStateEnabled = function(o, st, on)
	if not isEnum(st, "HumanoidStateType") or type(on) ~= "boolean" then
		error("SetStateEnabled(Enum.HumanoidStateType, boolean)", 2)
	end
	local int = internal(o)
	int.disabledStates = int.disabledStates or {}
	int.disabledStates[st] = not on or nil
end
hum.methods.GetStateEnabled = function(o, st)
	local d = internal(o).disabledStates
	return not (d and d[st])
end
hum.methods.Move = function(o, dir)
	assert(isV3(dir), "Humanoid:Move expects a Vector3")
	internal(o).move = dir
end
hum.methods.MoveTo = function(o, pos, part)
	assert(isV3(pos), "Humanoid:MoveTo expects a Vector3")
	o.WalkToPoint = pos
end
hum.methods.EquipTool = function(o, tool)
	if not (isInstance(tool) and tool:IsA("Tool")) then
		error("EquipTool: Tool expected", 2)
	end
	local char = charOf(o)
	if not char then
		return
	end
	for _, t in ipairs(Inst.GetChildren(char)) do
		if t ~= tool and t:IsA("Tool") then
			local player = MOCK.localPlayer
			t.Parent = player and Inst.FindFirstChildOfClass(player, "Backpack") or nil
		end
	end
	tool.Parent = char
end
hum.methods.UnequipTools = function(o)
	local char = charOf(o)
	local player = MOCK.localPlayer
	local backpack = player and Inst.FindFirstChildOfClass(player, "Backpack")
	for _, t in ipairs(char and Inst.GetChildren(char) or {}) do
		if t:IsA("Tool") then
			t.Parent = backpack
		end
	end
end
hum.methods.TakeDamage = function(o, n)
	o.Health = o.Health - n
end
hum.methods.GetAccessories = function(o)
	local out = {}
	for _, c in ipairs(Inst.GetChildren(charOf(o) or o)) do
		if c:IsA("Accoutrement") then
			table.insert(out, c)
		end
	end
	return out
end
hum.methods.AddAccessory = function(o, acc)
	acc.Parent = charOf(o)
end
hum.methods.RemoveAccessories = function(o)
	for _, a in ipairs(hum.methods.GetAccessories(o)) do
		a:Destroy()
	end
end
hum.methods.LoadAnimation = function(o, anim)
	return animatorLoad(ensureAnimator(o), anim)
end
hum.methods.GetPlayingAnimationTracks = function(o)
	local a = Inst.FindFirstChildOfClass(o, "Animator")
	return a and playingTracks(a) or {}
end
hum.methods.BuildRigFromAttachments = function() end
hum.methods.GetLimb = function()
	return Enum.Limb.Unknown
end

---------------------------------------------------------------- Characters
local R15 = {
	parts = {
		-- name, size, centre (character space, HumanoidRootPart centre = origin)
		{ "HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0) },
		{ "LowerTorso", Vector3.new(2, 0.5, 1), Vector3.new(0, -0.55, 0) },
		{ "UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 0.5, 0) },
		{ "Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.9, 0) },
		{ "LeftUpperArm", Vector3.new(0.9, 1.2, 0.9), Vector3.new(-1.5, 0.55, 0) },
		{ "LeftLowerArm", Vector3.new(0.85, 0.9, 0.85), Vector3.new(-1.5, -0.5, 0) },
		{ "LeftHand", Vector3.new(0.8, 0.4, 0.8), Vector3.new(-1.5, -1.15, 0) },
		{ "RightUpperArm", Vector3.new(0.9, 1.2, 0.9), Vector3.new(1.5, 0.55, 0) },
		{ "RightLowerArm", Vector3.new(0.85, 0.9, 0.85), Vector3.new(1.5, -0.5, 0) },
		{ "RightHand", Vector3.new(0.8, 0.4, 0.8), Vector3.new(1.5, -1.15, 0) },
		{ "LeftUpperLeg", Vector3.new(0.9, 1.2, 0.9), Vector3.new(-0.5, -1.4, 0) },
		{ "LeftLowerLeg", Vector3.new(0.85, 0.9, 0.85), Vector3.new(-0.5, -2.45, 0) },
		{ "LeftFoot", Vector3.new(0.9, 0.15, 1.1), Vector3.new(-0.5, -2.93, -0.1) },
		{ "RightUpperLeg", Vector3.new(0.9, 1.2, 0.9), Vector3.new(0.5, -1.4, 0) },
		{ "RightLowerLeg", Vector3.new(0.85, 0.9, 0.85), Vector3.new(0.5, -2.45, 0) },
		{ "RightFoot", Vector3.new(0.9, 0.15, 1.1), Vector3.new(0.5, -2.93, -0.1) },
	},
	joints = {
		-- Motor6D name, Part0, Part1 (the Motor6D lives in Part1), pivot (character space)
		{ "Root", "HumanoidRootPart", "LowerTorso", Vector3.new(0, -0.3, 0) },
		{ "Waist", "LowerTorso", "UpperTorso", Vector3.new(0, -0.3, 0) },
		{ "Neck", "UpperTorso", "Head", Vector3.new(0, 1.3, 0) },
		{ "LeftShoulder", "UpperTorso", "LeftUpperArm", Vector3.new(-1.25, 1.1, 0) },
		{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", Vector3.new(-1.5, -0.05, 0) },
		{ "LeftWrist", "LeftLowerArm", "LeftHand", Vector3.new(-1.5, -0.95, 0) },
		{ "RightShoulder", "UpperTorso", "RightUpperArm", Vector3.new(1.25, 1.1, 0) },
		{ "RightElbow", "RightUpperArm", "RightLowerArm", Vector3.new(1.5, -0.05, 0) },
		{ "RightWrist", "RightLowerArm", "RightHand", Vector3.new(1.5, -0.95, 0) },
		{ "LeftHip", "LowerTorso", "LeftUpperLeg", Vector3.new(-0.5, -0.8, 0) },
		{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", Vector3.new(-0.5, -2.0, 0) },
		{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", Vector3.new(-0.5, -2.85, 0) },
		{ "RightHip", "LowerTorso", "RightUpperLeg", Vector3.new(0.5, -0.8, 0) },
		{ "RightKnee", "RightUpperLeg", "RightLowerLeg", Vector3.new(0.5, -2.0, 0) },
		{ "RightAnkle", "RightLowerLeg", "RightFoot", Vector3.new(0.5, -2.85, 0) },
	},
}
MOCK.R15 = R15
local R6 = {
	parts = {
		{ "HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0) },
		{ "Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0) },
		{ "Head", Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0) },
		{ "Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0) },
		{ "Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0) },
		{ "Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0) },
		{ "Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0) },
	},
	-- the real R6 rig values: name, holder, Part0, Part1, C0, C1
	joints = {
		{ "RootJoint", "HumanoidRootPart", "HumanoidRootPart", "Torso", CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0) },
		{ "Neck", "Torso", "Torso", "Head", CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0) },
		{ "Left Shoulder", "Torso", "Torso", "Left Arm", CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
		{ "Right Shoulder", "Torso", "Torso", "Right Arm", CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
		{ "Left Hip", "Torso", "Torso", "Left Leg", CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
		{ "Right Hip", "Torso", "Torso", "Right Leg", CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	},
}
MOCK.R6 = R6

local function newI(cls, name, parent)
	local o = makeInstance(resolve(cls))
	if name then
		o.Name = name
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local function attachment(part, name, cf)
	local a = newI("Attachment", name, part)
	a.CFrame = cf
	return a
end
local function startIdle(animate)
	local char = parentOf(animate)
	local h = char and Inst.FindFirstChildOfClass(char, "Humanoid")
	if not h or not Inst.IsDescendantOf(char, workspaceObj) then
		return
	end
	local animator = Inst.FindFirstChildOfClass(h, "Animator")
	local idle = Inst.FindFirstChild(animate, "idle")
	local anim = idle and Inst.FindFirstChildOfClass(idle, "Animation")
	if animator and anim then
		animator:LoadAnimation(anim):Play()
	end
end
MOCK.startIdle = startIdle

-- Builds a character Model like the ones Roblox spawns (not parented). rig = "R15" (default) or "R6".
function MOCK.makeCharacter(rig, name)
	rig = rig or "R15"
	local spec = rig == "R6" and R6 or R15
	local m = newI("Model", name or "MockPlayer")
	local parts = {}
	for _, pd in ipairs(spec.parts) do
		local cls = (rig == "R15" and pd[1] ~= "HumanoidRootPart") and "MeshPart" or "Part"
		local p = newI(cls, pd[1])
		p.Size = pd[2]
		p.CFrame = CFrame.new(pd[3])
		p.Anchored = false
		p.CanCollide = false
		if pd[1] == "HumanoidRootPart" then
			p.Transparency = 1
		end
		p.Parent = m
		parts[pd[1]] = p
	end
	if rig == "R15" then
		local centre = {}
		for _, pd in ipairs(spec.parts) do
			centre[pd[1]] = pd[3]
		end
		for _, jd in ipairs(spec.joints) do
			local name, p0, p1, pivot = jd[1], jd[2], jd[3], jd[4]
			local c0 = CFrame.new(pivot - centre[p0])
			local c1 = CFrame.new(pivot - centre[p1])
			local j = newI("Motor6D", name)
			j.Part0 = parts[p0]
			j.Part1 = parts[p1]
			j.C0 = c0
			j.C1 = c1
			j.Parent = parts[p1]
			attachment(parts[p0], name .. "RigAttachment", c0)
			attachment(parts[p1], name .. "RigAttachment", c1)
		end
		attachment(parts.HumanoidRootPart, "RootAttachment", CFrame.identity)
		local grip = CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
		attachment(parts.RightHand, "RightGripAttachment", grip)
		attachment(parts.LeftHand, "LeftGripAttachment", grip)
		attachment(parts.Head, "HatAttachment", CFrame.new(0, 0.6, 0))
		attachment(parts.Head, "FaceFrontAttachment", CFrame.new(0, 0, -0.6))
	else
		for _, jd in ipairs(spec.joints) do
			local j = newI("Motor6D", jd[1])
			j.Part0 = parts[jd[3]]
			j.Part1 = parts[jd[4]]
			j.C0 = jd[5]
			j.C1 = jd[6]
			j.Parent = parts[jd[2]]
		end
		attachment(parts.HumanoidRootPart, "RootAttachment", CFrame.identity)
		attachment(parts.Head, "HatAttachment", CFrame.new(0, 0.5, 0))
		attachment(parts["Right Arm"], "RightGripAttachment", CFrame.new(0, -1, 0))
		local sm = newI("SpecialMesh", "Mesh", parts.Head)
		sm.MeshType = Enum.MeshType.Head
		sm.Scale = Vector3.new(1.25, 1.25, 1.25)
	end
	newI("Decal", "face", parts.Head).Texture = "rbxasset://textures/face.png"
	-- an accessory welded to the head, like most avatars have
	local hat = newI("Accessory", "MockHat")
	local handle = newI("Part", "Handle", hat)
	handle.Size = Vector3.new(1.4, 0.4, 1.4)
	handle.CanCollide = false
	handle.Massless = true
	local hatAtt = attachment(handle, "HatAttachment", CFrame.new(0, -0.2, 0))
	local headAtt = Inst.FindFirstChild(parts.Head, "HatAttachment")
	local aw = newI("Weld", "AccessoryWeld")
	aw.Part0 = handle
	aw.Part1 = parts.Head
	aw.C0 = hatAtt.CFrame
	aw.C1 = headAtt.CFrame
	aw.Parent = handle
	handle.CFrame = parts.Head.CFrame * headAtt.CFrame * hatAtt.CFrame:Inverse()
	hat.Parent = m
	newI("BodyColors", "Body Colors", m)
	local h = newI("Humanoid", "Humanoid")
	h.RigType = rig == "R6" and Enum.HumanoidRigType.R6 or Enum.HumanoidRigType.R15
	h.HipHeight = rig == "R6" and 0 or 2
	h.Parent = m
	newI("Animator", "Animator", h)
	local animate = newI("LocalScript", "Animate", m)
	local idle = newI("StringValue", "idle", animate)
	newI("Animation", "Animation1", idle).AnimationId = "rbxassetid://507766666"
	local ai = internal(animate)
	ai.onEnable = startIdle
	ai.cloneable = true
	m.PrimaryPart = parts.HumanoidRootPart
	m.Archivable = false -- like Roblox characters
	return m
end

local function playerModuleValue()
	local function strict(name, t)
		return setmetatable({}, {
			__index = function(_, k)
				local v = t[k]
				if v == nil then
					error(name .. " has no member " .. tostring(k), 2)
				end
				return v
			end,
			__newindex = function(_, k)
				error(name .. "." .. tostring(k) .. " cannot be assigned to", 2)
			end,
		})
	end
	local controls = strict("ControlModule", {
		Enable = function(_, enable)
			MOCK.controlsEnabled = enable ~= false
		end,
		Disable = function()
			MOCK.controlsEnabled = false
		end,
		GetMoveVector = function()
			return Vector3.zero
		end,
		GetActiveController = function()
			return nil
		end,
	})
	local cameras = strict("CameraModule", {})
	return strict("PlayerModule", {
		GetControls = function()
			return controls
		end,
		GetCameras = function()
			return cameras
		end,
		GetClickToMoveController = function()
			return nil
		end,
	})
end
-- Mock-provided modules (require(PlayerModule)); the bundle's require asks this first.
function MOCK.mockModuleOf(inst)
	local int = rawget(inst, "__int")
	return int and int.mockModule
end

-- Spawns (or respawns) the local player's character.
function MOCK.spawnCharacter(cf, rig)
	local player = assert(MOCK.localPlayer, "MOCK.setupClient first")
	local old = rawget(player, "__props").Character
	if old then
		fireIf(player, "CharacterRemoving", old)
		old:Destroy()
	end
	local char = MOCK.makeCharacter(rig or MOCK.rig or "R15", player.Name)
	char:PivotTo(cf or CFrame.new(0, (MOCK.groundY or 0) + 3, 0))
	char.Parent = workspaceObj
	player.Character = char
	startIdle(Inst.FindFirstChild(char, "Animate"))
	local cam = workspaceObj.CurrentCamera
	cam.CameraSubject = Inst.FindFirstChildOfClass(char, "Humanoid")
	cam.CameraType = Enum.CameraType.Custom
	local root = Inst.FindFirstChild(char, "HumanoidRootPart")
	cam.CFrame = CFrame.lookAt(root.Position + root.CFrame.LookVector * -MOCK.cameraZoom + Vector3.new(0, 4, 0), root.Position + Vector3.new(0, 1.5, 0))
	fireIf(player, "CharacterAdded", char)
	return char
end

-- Creates Players.LocalPlayer (PlayerScripts with a PlayerModule, PlayerGui, Backpack) and
-- its character; the calling (main) thread becomes client code. opts: name, userId, rig, spawn (CFrame).
function MOCK.setupClient(opts)
	opts = opts or {}
	assert(MOCK.localPlayer == nil, "MOCK.setupClient called twice")
	MOCK.running = true
	curCtx = "client"
	MOCK.rig = opts.rig or "R15"
	local player = makeInstance(resolve("Player"))
	player.Name = opts.name or "MockPlayer"
	player.DisplayName = player.Name
	internal(player).userId = opts.userId or 1
	local ps = newI("PlayerScripts", "PlayerScripts", player)
	local pm = newI("ModuleScript", "PlayerModule")
	internal(pm).mockModule = playerModuleValue
	pm.Parent = ps
	newI("PlayerGui", "PlayerGui", player)
	newI("Backpack", "Backpack", player)
	rawget(player, "__props").Parent = services.Players
	table.insert(children(services.Players), player)
	MOCK.localPlayer = player
	-- what Roblox copies on join / spawn
	local sps = Inst.FindFirstChild(services.StarterPlayer, "StarterPlayerScripts")
	for _, c in ipairs(sps and Inst.GetChildren(sps) or {}) do
		local cl = c:Clone()
		if cl then
			cl.Parent = ps
		end
	end
	for _, c in ipairs(Inst.GetChildren(services.StarterGui)) do
		local cl = c:Clone()
		if cl then
			cl.Parent = player.PlayerGui
		end
	end
	for _, c in ipairs(Inst.GetChildren(services.StarterPack)) do
		local cl = c:Clone()
		if cl then
			cl.Parent = player.Backpack
		end
	end
	MOCK.defaultCamera = true
	MOCK.spawnCharacter(opts.spawn)
	fireIf(services.Players, "PlayerAdded", player)
	return player
end

local playerMethods = RAW_DEFS.Player.methods
playerMethods.RequestStreamAroundAsync = function(o, pos, timeout)
	if not isV3(pos) then
		error("RequestStreamAroundAsync: Vector3 expected", 2)
	end
	table.insert(MOCK.streamRequests, { pos = pos, timeout = timeout, t = MOCK.clock })
	if canYield() then
		task.wait()
	end
end
playerMethods.GetNetworkPing = function()
	return 0.05
end
playerMethods.HasAppearanceLoaded = function()
	return true
end
playerMethods.ClearCharacterAppearance = function() end
playerMethods.DistanceFromCharacter = function(o, pos)
	local c = rawget(o, "__props").Character
	local head = c and Inst.FindFirstChild(c, "Head")
	return head and (head.Position - pos).Magnitude or 0
end
playerMethods.IsFriendsWith = function()
	return false
end
playerMethods.GetRankInGroup = function()
	return 0
end
playerMethods.GetRoleInGroup = function()
	return "Guest"
end
playerMethods.IsInGroup = function()
	return false
end
playerMethods.Kick = function(o, msg)
	MOCK.kicked = msg or ""
end
playerMethods.LoadCharacter = function(o)
	if curCtx == "client" then
		error("LoadCharacter can only be called by the server", 2)
	end
	MOCK.spawnCharacter()
end
RAW_DEFS.Players.methods = {
	GetPlayers = function()
		return MOCK.localPlayer and { MOCK.localPlayer } or {}
	end,
	GetPlayerFromCharacter = function(_, m)
		local p = MOCK.localPlayer
		if p and m ~= nil and rawget(p, "__props").Character == m then
			return p
		end
		return nil
	end,
	GetPlayerByUserId = function(_, id)
		local p = MOCK.localPlayer
		if p and p.UserId == id then
			return p
		end
		return nil
	end,
}

---------------------------------------------------------------- Joints
local function jointTarget(j, forward, p0cf, p1cf)
	-- forward: Part1 from Part0; otherwise Part0 from Part1
	local pr = rawget(j, "__props")
	local cls = rawget(j, "__class")
	if cls == "WeldConstraint" then
		local off = internal(j).offset or CFrame.identity
		if forward then
			return p0cf * off
		end
		return p1cf * off:Inverse()
	end
	local c0, c1 = pr.C0 or CFrame.identity, pr.C1 or CFrame.identity
	local t = (cls == "Motor6D" and pr.Transform) or CFrame.identity
	if forward then
		return p0cf * c0 * t * c1:Inverse()
	end
	return p1cf * c1 * t:Inverse() * c0:Inverse()
end
local function setPartCF(p, cf)
	local props = rawget(p, "__props")
	props.CFrame = cf
	props.Position = cf.Position
end
local function solveList(list)
	local adj, order = {}, {}
	for _, j in ipairs(list) do
		local pr = rawget(j, "__props")
		local p0, p1 = pr.Part0, pr.Part1
		if not adj[p0] then
			adj[p0] = {}
			table.insert(order, p0)
		end
		if not adj[p1] then
			adj[p1] = {}
			table.insert(order, p1)
		end
		table.insert(adj[p0], { j = j, other = p1, fwd = true })
		table.insert(adj[p1], { j = j, other = p0, fwd = false })
	end
	local done = {}
	for _, start in ipairs(order) do
		if not done[start] then
			-- collect the assembly and pick its root: anchored part, else HumanoidRootPart, else highest RootPriority
			local comp, seen, queue = {}, { [start] = true }, { start }
			while #queue > 0 do
				local p = table.remove(queue, 1)
				table.insert(comp, p)
				for _, e in ipairs(adj[p]) do
					if not seen[e.other] then
						seen[e.other] = true
						table.insert(queue, e.other)
					end
				end
			end
			local root = comp[1]
			local bestScore = -math.huge
			for _, p in ipairs(comp) do
				local score = (p.Anchored and 1e6 or 0) + (rawget(rawget(p, "__props"), "Name") == "HumanoidRootPart" and 1e3 or 0) + (p.RootPriority or 0)
				if score > bestScore then
					root, bestScore = p, score
				end
			end
			done[root] = true
			queue = { root }
			while #queue > 0 do
				local p = table.remove(queue, 1)
				local pcf = rawget(p, "__props").CFrame
				for _, e in ipairs(adj[p]) do
					local o = e.other
					if not done[o] then
						done[o] = true
						if not o.Anchored then
							if e.fwd then
								setPartCF(o, jointTarget(e.j, true, pcf, nil))
							else
								setPartCF(o, jointTarget(e.j, false, nil, pcf))
							end
						end
						table.insert(queue, o)
					end
				end
			end
		end
	end
end
-- Solves the joints (Motor6D with Transform, Weld, WeldConstraint) of one model, or of everything
-- the engine simulates (Workspace and WorldModels) when model is nil.
function MOCK.solveJoints(model)
	local list, alive = {}, {}
	local warnedViewport = MOCK.__warnedViewport
	for _, j in ipairs(MOCK._joints) do
		if not rawget(j, "__destroyed") then
			table.insert(alive, j)
			local pr = rawget(j, "__props")
			if pr.Enabled ~= false and pr.Part0 and pr.Part1 and pr.Part0 ~= pr.Part1 then
				if model then
					if Inst.IsDescendantOf(pr.Part0, model) and Inst.IsDescendantOf(pr.Part1, model) then
						table.insert(list, j)
					end
				elseif isSimulated(j) and isSimulated(pr.Part0) and isSimulated(pr.Part1) then
					table.insert(list, j)
				elseif not warnedViewport and rawget(j, "__class") == "Motor6D" then
					local int = rawget(j, "__int")
					if int and int.writer ~= "animator" and int.writeFrame == MOCK.frame and Inst.FindFirstAncestorOfClass(j, "ViewportFrame") then
						warnedViewport = true
						MOCK.__warnedViewport = true
						mockWarn("Motor6D.Transform set on a rig inside a ViewportFrame without a WorldModel: Roblox doesn't solve joints there")
					end
				end
			end
		end
	end
	if not model then
		MOCK._joints = alive
	end
	solveList(list)
end

---------------------------------------------------------------- Per-frame engine work
local function defaultCamera(dt)
	if not MOCK.defaultCamera then
		return
	end
	local cam = workspaceObj.CurrentCamera
	local ct = cam.CameraType.Name
	if ct ~= "Custom" and ct ~= "Follow" and ct ~= "Track" and ct ~= "Attach" and ct ~= "Watch" then
		return
	end
	local subj = cam.CameraSubject
	local focus
	if subj and subj:IsA("Humanoid") then
		local root = subj.RootPart
		if root then
			focus = root.Position + Vector3.new(0, 1.5, 0) + subj.CameraOffset
		end
	elseif subj and isPart(subj) then
		focus = subj.Position
	end
	if focus then
		local look = cam.CFrame.LookVector
		cam.CFrame = CFrame.lookAt(focus - look * MOCK.cameraZoom, focus)
		cam.Focus = CFrame.new(focus)
	end
end
local function stepSounds(dt)
	for _, s in ipairs(table.clone(MOCK._sounds)) do
		if rawget(s, "__destroyed") then
			soundStop(s, false)
		else
			local props = rawget(s, "__props")
			props.TimePosition = (props.TimePosition or 0) + dt * (props.PlaybackSpeed or 1)
			local len = soundLength(s)
			if len > 0 and props.TimePosition >= len then
				if props.Looped then
					props.TimePosition = props.TimePosition % len
					fireIf(s, "DidLoop", props.SoundId or "", 1)
				else
					soundStop(s, true)
					fireIf(s, "Ended", props.SoundId or "")
				end
			end
		end
	end
end
local function deliverRemotes()
	local q = MOCK._remoteQueue
	if #q == 0 then
		return
	end
	MOCK._remoteQueue = {}
	for _, r in ipairs(q) do
		if not rawget(r.remote, "__destroyed") then
			if r.dir == "server" then
				fire(getSignal(r.remote, "OnServerEvent"), r.player, table.unpack(r.args, 1, r.args.n))
			else
				fire(getSignal(r.remote, "OnClientEvent"), table.unpack(r.args, 1, r.args.n))
			end
		end
	end
end
local function checkHighlights()
	local n, alive = 0, {}
	for _, h in ipairs(MOCK._highlights) do
		if not rawget(h, "__destroyed") then
			table.insert(alive, h)
			if h.Enabled and Inst.IsDescendantOf(h, gameObj) then
				n += 1
			end
		end
	end
	MOCK._highlights = alive
	MOCK.activeHighlights = n
	if n > 31 then
		mockWarn("more than 31 Highlights enabled at once (Roblox renders at most 31)")
	end
end
local function runRender(dt)
	local list = table.clone(renderBindings)
	local camDone = false
	local camPriority = Enum.RenderPriority.Camera.Value
	for _, b in ipairs(list) do
		if not camDone and b.priority >= camPriority then
			camDone = true
			defaultCamera(dt)
		end
		spawnThread(b.fn, b.ctx, dt)
	end
	if not camDone then
		defaultCamera(dt)
	end
end

-- Advances the simulated clock by one frame and runs the engine's frame phases in Roblox order:
--   remote events arrive, deferred threads, tweens,
--   render: BindToRenderStep callbacks by priority (the default camera runs at Camera = 200),
--           then PreRender and RenderStepped connections,
--   PreAnimation, the Animator (playing tracks write Motor6D.Transform),
--   PreSimulation and Stepped, joint solving (Part1 = Part0 * C0 * Transform * C1:Inverse()), sounds,
--   PostSimulation and Heartbeat, then threads waiting in task.wait/task.delay.
-- Returns the real (CPU) time spent.
function MOCK.step(dt)
	dt = dt or 1 / 60
	local t0 = realClock()
	MOCK.frame += 1
	MOCK.clock += dt
	local rs = services.RunService
	deliverRemotes()
	flushDeferred()
	stepTweens(dt)
	flushDeferred()
	runRender(dt)
	fireIf(rs, "PreRender", dt)
	fireIf(rs, "RenderStepped", dt)
	flushDeferred()
	fireIf(rs, "PreAnimation", dt)
	stepAnimators(dt)
	flushDeferred()
	fireIf(rs, "PreSimulation", dt)
	fireIf(rs, "Stepped", MOCK.clock, dt)
	flushDeferred()
	MOCK.solveJoints()
	stepSounds(dt)
	fireIf(rs, "PostSimulation", dt)
	fireIf(rs, "Heartbeat", dt)
	flushDeferred()
	resumeWaiting()
	flushDeferred()
	checkHighlights()
	return realClock() - t0
end
-- Steps for `seconds` of simulated time.
function MOCK.run(seconds, dt)
	dt = dt or 1 / 60
	local n = math.max(1, math.floor(seconds / dt + 0.5))
	for _ = 1, n do
		MOCK.step(dt)
	end
end

-- Would Roblox run this script where it is? (LocalScripts only run under the player or in
-- ReplicatedFirst; legacy Scripts only in Workspace/ServerScriptService.)
local function scriptRunsHere(inst, ctx)
	if not Inst.IsDescendantOf(inst, gameObj) then
		return false, "not in the DataModel"
	end
	local function under(x)
		return x ~= nil and Inst.IsDescendantOf(inst, x)
	end
	local player = MOCK.localPlayer
	if inst:IsA("LocalScript") then
		local ok = under(services.ReplicatedFirst)
			or (player and (under(player) or under(rawget(player, "__props").Character)))
		return ok, "LocalScripts only run in PlayerScripts, PlayerGui, Backpack, the character or ReplicatedFirst"
	end
	local rc = inst.RunContext.Name
	if rc == "Legacy" then
		return under(workspaceObj) or under(services.ServerScriptService), "legacy Scripts only run in Workspace or ServerScriptService"
	end
	if under(services.ServerStorage) or under(services.StarterPlayer) or under(services.StarterGui) or under(services.StarterPack) then
		return false, "RunContext scripts don't run in storage/starter containers"
	end
	return true
end
-- Starts a Script/LocalScript body (the bundle's runScript uses this): runs it now in a new
-- thread with the right context. Returns the thread, or nil if Roblox wouldn't run it.
function MOCK.startScript(inst, body, force)
	assert(isInstance(inst) and inst:IsA("BaseScript"), "startScript expects a Script or LocalScript")
	local ctx
	if inst:IsA("LocalScript") then
		ctx = "client"
	else
		ctx = inst.RunContext.Name == "Client" and "client" or "server"
	end
	if not force then
		local ok, why = scriptRunsHere(inst, ctx)
		if not ok then
			mockWarn("script " .. Inst.GetFullName(inst) .. " would not run: " .. why)
			return nil
		end
		if not inst.Enabled then
			mockWarn("script " .. Inst.GetFullName(inst) .. " is disabled")
			return nil
		end
	end
	return spawnThread(body, ctx)
end

-- Writable property names of an instance (for snapshot/restore checks in drivers).
function MOCK.propertyNames(o)
	local c = defOf(o)
	local out = {}
	for k in pairs(c.props) do
		if k ~= "Parent" then
			table.insert(out, k)
		end
	end
	if c.permissive then
		for k, v in pairs(rawget(o, "__props")) do
			if k ~= "Parent" and type(v) ~= "function" and c.props[k] == nil then
				table.insert(out, k)
			end
		end
	end
	table.sort(out)
	return out
end

---------------------------------------------------------------- Services
local function makeService(name)
	local c = resolve(name)
	assert(c, "no class for service " .. name)
	return setmetatable({ __class = c.name, __def = c, __props = { Name = name }, __children = {}, __attrs = {}, __service = true }, instMeta)
end
local function attach(o, parent)
	rawget(o, "__props").Parent = parent
	table.insert(children(parent), o)
end

gameObj = makeService("DataModel")
rawget(gameObj, "__props").Name = "Game"
workspaceObj = makeService("Workspace")
attach(workspaceObj, gameObj)
terrain = makeService("Terrain")
attach(terrain, workspaceObj)
rawget(workspaceObj, "__props").Terrain = terrain

MOCK.materialColors = {}
local function checkMat(m)
	assert(isEnum(m, "Material"), "terrain material must be Enum.Material")
end
local TerrainMethods = {}
function TerrainMethods.Clear() end
MOCK.fills = {}
function TerrainMethods.FillBlock(_, cf, size, mat)
	assert(MOCK.isCF(cf) and MOCK.isV3(size), "FillBlock(CFrame, Vector3, Material)")
	checkMat(mat)
	MOCK.fillCalls += 1
	-- the open-sea fills are huge; only keep the small ones (water features, terrain pads)
	if size.X <= 200 and size.Z <= 200 then
		table.insert(MOCK.fills, { "block", cf, size, mat.Name })
	end
end
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

local SERVICE_NAMES = {
	"Lighting", "ReplicatedStorage", "ReplicatedFirst", "ServerStorage", "ServerScriptService", "StarterPlayer",
	"StarterGui", "StarterPack", "SoundService", "ChangeHistoryService", "RunService", "Players", "TweenService",
	"UserInputService", "ContextActionService", "GuiService", "Debris", "CollectionService", "ContentProvider",
	"HttpService", "Teams",
}
services.Workspace = workspaceObj
for _, n in ipairs(SERVICE_NAMES) do
	local s = makeService(n)
	attach(s, gameObj)
	services[n] = s
end
local sps = makeService("StarterPlayerScripts")
attach(sps, services.StarterPlayer)
local scs = makeService("StarterCharacterScripts")
attach(scs, services.StarterPlayer)

game = gameObj
workspace = workspaceObj
MOCK.services = services

return MOCK
