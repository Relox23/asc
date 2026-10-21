--[[
	Unit tests for src/IntroCutscene/Timeline.luau and Convert.luau (plain Luau, no Roblox).

	    luau tools/tests/timeline_test.luau

	Convert needs CFrame/Vector3, so a small shim of both is defined first.
	Also loads the IntroData module (the stub or the real export) and checks
	that every track samples to finite numbers and unit quaternions.
]]

-- Vector3 / CFrame shim ----------------------------------------------------------------------------------
local V = {}
V.__index = function(v, k)
	if k == "X" then
		return v.x
	elseif k == "Y" then
		return v.y
	elseif k == "Z" then
		return v.z
	elseif k == "Magnitude" then
		return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	elseif k == "Unit" then
		local m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
		return V.new(v.x / m, v.y / m, v.z / m)
	end
	return V[k]
end
function V.new(x, y, z)
	return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V)
end
V.__add = function(a, b)
	return V.new(a.x + b.x, a.y + b.y, a.z + b.z)
end
V.__sub = function(a, b)
	return V.new(a.x - b.x, a.y - b.y, a.z - b.z)
end
V.__unm = function(a)
	return V.new(-a.x, -a.y, -a.z)
end
V.__mul = function(a, b)
	if type(a) == "number" then
		return V.new(a * b.x, a * b.y, a * b.z)
	elseif type(b) == "number" then
		return V.new(a.x * b, a.y * b, a.z * b)
	end
	return V.new(a.x * b.x, a.y * b.y, a.z * b.z)
end
V.__div = function(a, b)
	return V.new(a.x / b, a.y / b, a.z / b)
end
function V.Dot(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z
end
function V.Cross(a, b)
	return V.new(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end
V.zero = V.new(0, 0, 0)
V.xAxis, V.yAxis, V.zAxis = V.new(1, 0, 0), V.new(0, 1, 0), V.new(0, 0, 1)
local Vector3 = { new = V.new, zero = V.zero, xAxis = V.xAxis, yAxis = V.yAxis, zAxis = V.zAxis }

local C = {}
local function cf(px, py, pz, m)
	return setmetatable({ p = V.new(px, py, pz), m = m }, C)
end
local function mmul(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			local s = 0
			for k = 0, 2 do
				s += a[i * 3 + k + 1] * b[k * 3 + j + 1]
			end
			r[i * 3 + j + 1] = s
		end
	end
	return r
end
local function mvec(m, v)
	return V.new(m[1] * v.x + m[2] * v.y + m[3] * v.z, m[4] * v.x + m[5] * v.y + m[6] * v.z, m[7] * v.x + m[8] * v.y + m[9] * v.z)
end
local function transpose(m)
	return { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
end
local ID = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
C.__index = function(c, k)
	local m = c.m
	if k == "Position" then
		return c.p
	elseif k == "LookVector" then
		return V.new(-m[3], -m[6], -m[9])
	elseif k == "UpVector" then
		return V.new(m[2], m[5], m[8])
	elseif k == "RightVector" then
		return V.new(m[1], m[4], m[7])
	elseif k == "Rotation" then
		return cf(0, 0, 0, m)
	elseif k == "X" then
		return c.p.x
	elseif k == "Y" then
		return c.p.y
	elseif k == "Z" then
		return c.p.z
	end
	return C[k]
end
C.__mul = function(a, b)
	if getmetatable(b) == V then
		return mvec(a.m, b) + a.p
	end
	local p = mvec(a.m, b.p) + a.p
	return cf(p.x, p.y, p.z, mmul(a.m, b.m))
end
function C.Inverse(c)
	local mt = transpose(c.m)
	local p = mvec(mt, -c.p)
	return cf(p.x, p.y, p.z, mt)
end
function C.VectorToWorldSpace(c, v)
	return mvec(c.m, v)
end
function C.VectorToObjectSpace(c, v)
	return mvec(transpose(c.m), v)
end
local function quatMatrix(x, y, z, w)
	return {
		1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
		2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
		2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y),
	}
end
local function rx(a)
	local c, s = math.cos(a), math.sin(a)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function ry(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rz(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end
local CFrame = {
	new = function(a, b, c, qx, qy, qz, qw)
		if a == nil then
			return cf(0, 0, 0, ID)
		end
		if type(a) == "table" then
			return cf(a.x, a.y, a.z, ID)
		end
		if qw ~= nil then
			local n = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
			return cf(a, b, c, quatMatrix(qx / n, qy / n, qz / n, qw / n))
		end
		return cf(a, b, c, ID)
	end,
	Angles = function(a, b, c)
		return cf(0, 0, 0, mmul(rx(a), mmul(ry(b), rz(c))))
	end,
	lookAt = function(at, target, up)
		up = up or V.yAxis
		local look = (target - at).Unit
		local right = look:Cross(up).Unit
		local up2 = right:Cross(look)
		return cf(at.x, at.y, at.z, { right.x, up2.x, -look.x, right.y, up2.y, -look.y, right.z, up2.z, -look.z })
	end,
}
CFrame.identity = CFrame.new()

-- test harness -------------------------------------------------------------------------------------------
local failures, checks = 0, 0
local function check(cond, what)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL: " .. what)
	end
end
local function near(a, b, eps, what)
	check(math.abs(a - b) <= (eps or 1e-9), string.format("%s: got %.9f want %.9f", what, a, b))
end

local Timeline = require("../../src/IntroCutscene/Timeline")
local Convert = require("../../src/IntroCutscene/Convert")
Convert.useMath(CFrame, Vector3)

local function qz(angle)
	return { math.cos(angle / 2), 0, 0, math.sin(angle / 2) }
end
local function flat(list)
	local out = {}
	for _, v in ipairs(list) do
		for _, c in ipairs(v) do
			table.insert(out, c)
		end
	end
	return out
end
local function quatAngleZ(q)
	return 2 * math.atan2(q[4], q[1])
end

-- 1. linear motion, slerp, clamps ----------------------------------------------------------------------
do
	local pos, rot, visible, glow, grounded = {}, {}, {}, {}, {}
	for i = 0, 10 do
		table.insert(pos, { i, 2 * i, -i })
		table.insert(rot, qz(i * 0.1))
		visible[i + 1] = i >= 2 and 1 or 0
		glow[i + 1] = i * 0.5
		grounded[i + 1] = i % 2
	end
	local tl = Timeline.new({
		fps = 30,
		duration = 3,
		tracks = {
			A = { stage = "world", rate = 10, t0 = 1, n = 11, pos = flat(pos), rot = flat(rot), channels = { visible = visible, glow = glow, isGrounded = grounded } },
		},
	})
	local A = tl:track("A")
	check(A ~= nil and A.t1 == 2, "track A exists, t1 = 2")
	local s = A:sample(1.55)
	near(s.pos[1], 5.5, 1e-9, "linear x")
	near(s.pos[2], 11, 1e-9, "linear y")
	near(s.pos[3], -5.5, 1e-9, "linear z")
	near(quatAngleZ(s.rot), 0.55, 1e-9, "slerp angle")
	near(s.channels.glow, 2.75, 1e-12, "scalar linear")
	near(s.channels.visible, 1, 0, "step visible (sample 5)")
	near(s.channels.isGrounded, 1, 0, "step is* channel (floor -> sample 5)")
	near(A:sample(1.19).channels.visible, 0, 0, "step: between 1 and 2 holds sample 1")
	near(A:sample(1.2).channels.visible, 1, 0, "step: exactly on sample 2")
	near(A:channel("glow", 1.25), 1.25, 1e-12, "channel()")
	check(A:channel("nope", 1) == nil, "missing channel -> nil")
	s = A:sample(0)
	near(s.pos[1], 0, 0, "clamp before t0")
	near(A:sample(99).pos[2], 20, 0, "clamp after the end")
	near(A:sample(99).channels.glow, 5, 0, "scalar clamp after the end")
	check(A:sample(1.3) == A:sample(1.4), "sample table is reused")
	near(s.scale, 1, 0, "no scale -> 1")
end

-- 2. cuts ------------------------------------------------------------------------------------------------
do
	local pos = {}
	for i = 0, 10 do
		local x = i < 5 and i or 100 + i
		table.insert(pos, { x, 0, 0 })
	end
	local rate, t0 = 10, 0
	local cutAt = t0 + 5 / rate -- exactly on sample 5
	local tl = Timeline.new({
		fps = 30,
		duration = 1,
		cuts = { cutAt, 0.85 }, -- second cut between samples 8 and 9
		tracks = { B = { stage = "camera", rate = rate, t0 = t0, n = 11, pos = flat(pos), rot = flat({ qz(0), qz(0), qz(0), qz(0), qz(0), qz(1), qz(1), qz(1), qz(1), qz(1), qz(1) }) } },
	})
	local B = tl:track("B")
	near(B:sample(0.45).pos[1], 4, 0, "just before the cut: holds sample 4")
	near(B:sample(0.4999).pos[1], 4, 0, "right before the cut: still sample 4")
	near(B:sample(0.5).pos[1], 105, 0, "at the cut: sample 5")
	near(B:sample(0.55).pos[1], 105.5, 1e-9, "after the cut: no blending, mirrored neighbour")
	near(B:sample(0.35).pos[1], 3.5, 1e-9, "before the cut: spline does not reach across it")
	near(B:sample(0.45).rot[1], 1, 1e-12, "rotation held before the cut")
	near(quatAngleZ(B:sample(0.5).rot), 1, 1e-9, "rotation after the cut")
	-- a cut between samples: (t8, t9] contains 0.85
	near(B:sample(0.82).pos[1], 108, 0, "before an off-grid cut: sample 8")
	near(B:sample(0.86).pos[1], 109, 0, "after an off-grid cut: sample 9")
	near(B:sample(0.75).pos[1], 107.5, 1e-9, "spline before an off-grid cut")
	check(tl:cutBetween(0.4, 0.5) == 0.5, "cutBetween includes the end")
	check(tl:cutBetween(0.5, 0.6) == nil, "cutBetween excludes the start")
end

-- 3. hemisphere continuity -----------------------------------------------------------------------------
do
	local q1 = qz(0.2)
	local neg = { -q1[1], -q1[2], -q1[3], -q1[4] }
	local tl = Timeline.new({ tracks = { R = { rate = 1, t0 = 0, n = 2, pos = { 0, 0, 0, 0, 0, 0 }, rot = { 1, 0, 0, 0, neg[1], neg[2], neg[3], neg[4] } } } })
	local s = tl:track("R"):sample(0.5)
	local a = quatAngleZ(s.rot)
	if a > math.pi then
		a -= 2 * math.pi
	end
	near(math.abs(a), 0.1, 1e-9, "slerp takes the short way")
	local len = math.sqrt(s.rot[1] ^ 2 + s.rot[2] ^ 2 + s.rot[3] ^ 2 + s.rot[4] ^ 2)
	near(len, 1, 1e-12, "unit quaternion")
end

-- 4. centripetal Catmull-Rom on a curve -----------------------------------------------------------------
do
	-- samples on a circle; the spline between samples should stay close to the circle
	local pos, n, r = {}, 40, 50
	for i = 0, n - 1 do
		local a = i / (n - 1) * math.pi
		table.insert(pos, { r * math.cos(a), r * math.sin(a), 0 })
	end
	local tl = Timeline.new({ tracks = { Circ = { rate = 30, t0 = 0, n = n, pos = flat(pos) } } })
	local T = tl:track("Circ")
	local worst = 0
	for k = 1, 200 do
		local t = (k / 201) * (n - 1) / 30
		local s = T:sample(t)
		local d = math.abs(math.sqrt(s.pos[1] ^ 2 + s.pos[2] ^ 2) - r)
		worst = math.max(worst, d)
	end
	check(worst < 0.01, string.format("spline stays on the circle (worst %.5f)", worst))
	-- uneven spacing and a repeated sample must not produce NaNs
	local tl2 = Timeline.new({ tracks = { U = { rate = 30, t0 = 0, n = 5, pos = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 10.001, 0, 0 } } } })
	for k = 0, 40 do
		local s = tl2:track("U"):sample(k / 300)
		check(s.pos[1] == s.pos[1] and math.abs(s.pos[1]) < 20, "degenerate spline stays finite")
	end
end

-- 5. markers ----------------------------------------------------------------------------------------------
do
	local kind, args = Timeline.parseMarker("shake:0.4:1.6")
	check(kind == "shake" and args[1] == 0.4 and args[2] == 1.6, "parse shake")
	kind, args = Timeline.parseMarker("bars:in:1.0")
	check(kind == "bars" and args[1] == "in" and args[2] == 1, "parse bars")
	kind, args = Timeline.parseMarker("cut")
	check(kind == "cut" and #args == 0, "parse cut")
	local tl = Timeline.new({
		markers = {
			{ t = 0, name = "bars:in:1.0" },
			{ t = 0, name = "fade:from_black:0.8" },
			{ t = 1, name = "flash:white:0.3" },
			{ t = 2.5, name = "impact:white" },
			{ t = 2.5, name = "impact:black" },
			{ t = 4, name = "end" },
		},
		stageSwitch = 2,
	})
	local fired = {}
	local cur = tl:cursor()
	local function rec(m)
		table.insert(fired, m.name)
	end
	check(cur:advance(0, rec) == 2, "two markers at t 0 fire on the first frame")
	check(cur:advance(3, rec) == 3, "a long frame fires everything it passed")
	check(cur:advance(3, rec) == 0, "markers fire only once")
	check(fired[4] == "impact:white" and fired[5] == "impact:black", "same-time markers keep their order")
	check(cur:peek().name == "end", "peek")
	check(cur:advance(10, rec) == 1 and cur:peek() == nil, "the rest")
	cur:reset(1)
	check(cur:peek().name == "impact:white", "reset(t)")
	check(#tl:markersOf("impact") == 2, "markersOf")
	check(tl:firstMarker("impact", "black").t == 2.5, "firstMarker with arg")
	check(tl:stageAt(1.999) == "space" and tl:stageAt(2) == "world", "stageAt")
	-- an erroring handler doesn't make the marker fire twice
	cur:reset()
	pcall(function()
		cur:advance(0, function()
			error("boom")
		end)
	end)
	check(cur:advance(0, rec) == 1, "marker skipped after an error in its handler")
end

-- 6. character -------------------------------------------------------------------------------------------
do
	local joints = {}
	for _, name in ipairs(Timeline.JOINT_NAMES) do
		joints[name] = flat({ qz(0), qz(0.4), qz(0.8) })
	end
	local tl = Timeline.new({
		fps = 30,
		character = {
			rate = 10,
			t0 = 1,
			n = 3,
			root = { pos = { 0, 0, 3, 0, 1, 3, 0, 2, 3 }, rot = flat({ qz(0), qz(0), qz(0) }) },
			joints = joints,
			rootLoc = { 0, 0, 0, 0, 0.2, 0, 0, 0.4, 0 },
			channels = { visible = { 0, 1, 1 }, form = { 0, 0.5, 1 } },
		},
	})
	local c = tl:character(1.05)
	near(c.root.pos[2], 0.5, 1e-9, "character root position")
	near(quatAngleZ(c.joints.RightElbow), 0.2, 1e-9, "joint slerp")
	near(c.rootLoc[2], 0.1, 1e-12, "root location linear")
	near(c.channels.visible, 0, 0, "character visible step")
	near(c.channels.form, 0.25, 1e-12, "character form linear")
	check(c.t0 == 1 and c.t1 == 1.2, "character t0/t1")
	near(tl:character(0).root.pos[2], 0, 0, "character clamps before t0")
	check(tl:characterTrack():channel("form", 2) == 1, "character channel()")
end

-- 7. Convert ------------------------------------------------------------------------------------------
do
	local ok, msg = Convert.selfCheck()
	check(ok, "Convert.selfCheck: " .. tostring(msg))
	-- rotFromQuat == C * R * C^T for random quaternions
	local Cm = { 1, 0, 0, 0, 0, 1, 0, -1, 0 }
	local seed = 12345
	local function rnd()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648 * 2 - 1
	end
	local worst = 0
	for _ = 1, 50 do
		local w, x, y, z = rnd(), rnd(), rnd(), rnd()
		local n = math.sqrt(w * w + x * x + y * y + z * z)
		w, x, y, z = w / n, x / n, y / n, z / n
		local Rbl = quatMatrix(x, y, z, w)
		local want = mmul(mmul(Cm, Rbl), transpose(Cm))
		local got = Convert.rotFromQuat(w, x, y, z).m
		for k = 1, 9 do
			worst = math.max(worst, math.abs(want[k] - got[k]))
		end
	end
	check(worst < 1e-9, string.format("rotFromQuat = C R C^T (worst %.2e)", worst))
	-- asset rule: a point given in asset-local Blender coordinates lands where Blender has it
	local origin = CFrame.new(5, 6, 7) * CFrame.Angles(0, 0.7, 0)
	local p, q = { 3, -4, 2 }, { math.cos(0.4), 0.3 * math.sin(0.4), 0, math.sqrt(1 - 0.09) * math.sin(0.4) }
	local acf = Convert.assetCF(origin, p, q)
	local local_ = { 1, 2, 3 }
	local Rb = quatMatrix(q[2], q[3], q[4], q[1])
	local worldBl = mvec(Rb, V.new(local_[1], local_[2], local_[3])) + V.new(p[1], p[2], p[3])
	local want = origin * Convert.pos(worldBl.x, worldBl.y, worldBl.z)
	local got = acf * Convert.fromBlender(local_[1], local_[2], local_[3])
	check((want - got).Magnitude < 1e-9, "assetCF * fromBlender = origin * R(Blender world point)")
	-- a character-space offset (Roblox x, y, z) is Blender (x, -z, y) in the armature's frame
	local ccf = Convert.cf(origin, p, q)
	local offR = V.new(0.5, 1.5, -2)
	local blLocal = V.new(offR.x, -offR.z, offR.y)
	local w2 = mvec(Rb, blLocal) + V.new(p[1], p[2], p[3])
	check((origin * Convert.pos(w2.x, w2.y, w2.z) - ccf * offR).Magnitude < 1e-9, "cf maps character space like the armature")
end

-- 8. the IntroData module (stub or real export) ------------------------------------------------------------
do
	local data = require("../../src/IntroCutscene/IntroData")
	local tl = Timeline.new(data)
	check(data.version == 1, "IntroData version 1")
	check(type(data.duration) == "number" and data.duration > 0, "duration")
	local last = -1
	local stageMarker
	for _, m in ipairs(data.markers) do
		check(m.t >= last, "markers sorted (" .. m.name .. ")")
		last = m.t
		if m.name == "stage:world" then
			stageMarker = m.t
		end
	end
	check(stageMarker ~= nil and math.abs(stageMarker - data.stageSwitch) < 1e-6, "stage:world marker at stageSwitch")
	for _, c in ipairs(data.cuts) do
		local found = false
		for _, m in ipairs(data.markers) do
			if m.name == "cut" and math.abs(m.t - c) < 1e-6 then
				found = true
			end
		end
		check(found, "cut marker for cut " .. c)
	end
	local badPos, badRot, badCh = 0, 0, 0
	local names = tl:trackNames()
	for _, name in ipairs(names) do
		local d = data.tracks[name]
		check(#d.pos == 3 * d.n and #d.rot == 4 * d.n, name .. ": pos/rot sizes match n")
		for ch, values in pairs(d.channels or {}) do
			check(#values == d.n, name .. "." .. ch .. ": one value per sample")
		end
		check(d.stage == "space" or d.stage == "world" or d.stage == "camera", name .. ": stage field")
		local T = tl:track(name)
		for k = 0, 400 do
			local t = data.duration * k / 400
			local s = T:sample(t)
			for i = 1, 3 do
				if s.pos[i] ~= s.pos[i] or math.abs(s.pos[i]) > 1e6 then
					badPos += 1
				end
			end
			local len = math.sqrt(s.rot[1] ^ 2 + s.rot[2] ^ 2 + s.rot[3] ^ 2 + s.rot[4] ^ 2)
			if math.abs(len - 1) > 1e-6 then
				badRot += 1
			end
			for _, v in pairs(s.channels) do
				if v ~= v then
					badCh += 1
				end
			end
		end
	end
	check(badPos == 0 and badRot == 0 and badCh == 0, string.format("IntroData samples finite (%d %d %d)", badPos, badRot, badCh))
	local ct = tl:characterTrack()
	check(ct ~= nil and #ct.jointNames == 15, "character with 15 joints")
	-- the stub (8 s) aims its camera exactly at the soul core during the space stage: checks the camera convention
	local cam, core = tl:track("Camera"), tl:track("SoulCore")
	if cam and core and data.duration < 10 then
		local worst = 0
		local id = CFrame.new()
		for k = 0, math.floor(data.stageSwitch * 30) - 1 do
			local t = k / 30
			local c = cam:sample(t)
			local look = Convert.cameraCF(id, c.pos, c.rot).LookVector
			local up = Convert.cameraCF(id, c.pos, c.rot).UpVector
			local eye = Convert.posOf(c.pos)
			local target = Convert.posOf(core:sample(t).pos)
			local want = (target - eye).Unit
			worst = math.max(worst, math.deg(math.acos(math.clamp(look:Dot(want), -1, 1))))
			check(up.y > 0, "camera up has +Y")
		end
		print(string.format("camera->core aim error (stub, space stage): %.4f deg", worst))
		check(worst < 0.5, "camera looks at the core (stub convention check)")
	end

	-- speed: a frame = 12 tracks + the character
	local t0 = os.clock()
	local frames = 5000
	for f = 1, frames do
		local t = (f / frames) * data.duration
		for _, name in ipairs(names) do
			tl:track(name):sample(t)
		end
		tl:character(t)
	end
	local us = (os.clock() - t0) / frames * 1e6
	print(string.format("sampling %d tracks + character: %.1f us per frame", #names, us))
	check(us < 2000, "sampling is fast")
end

print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
	error("timeline tests failed")
end
