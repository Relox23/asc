--[[
	Parity test: the Luau Timeline sampling of src/IntroCutscene/IntroData.luau against the values
	Blender evaluated for the same (sub-frame) times, tools/tests/intro_parity.luau. Both files are
	written together by tools/blender/intro/export_intro.py (docs/intro/DESIGN.md §8, §9).

	    luau tools/tests/intro_parity_test.luau

	Tolerances (DESIGN §9): position < 0.05 studs (camera < 0.02), rotation < 0.5 deg, scalar
	channels < 0.01 (fov: 0.01 deg), joint rotations < 0.75 deg, or 12 % of the motion between the
	two samples around t when that is larger (interpolation drift during very fast motion). Fixture times inside a sample
	interval that contains a cut are skipped (the runtime holds the sample on t's side of a cut on
	purpose; the exporter already avoids the 30 Hz ones, this catches lower-rate tracks). Values the
	fixture lists in an entry's `held` (Blender holds them over that frame interval: a CONSTANT key
	or a constraint switch that is not at a cut, which the runtime blends over one sample) are not
	compared either; they are counted in the summary.
	Also checks the Blender -> Roblox conventions on real data with Convert (CFrame shim): the camera
	looks along R(Blender camera -Z) with R(+Y) up (Convert.cameraCF), and the sword's blade
	(Blender +Z) is the asset's UpVector (Convert.assetCF).
	Prints the worst cases per kind, "FAIL ..." lines, and errors at the end when anything failed.
]]

-- minimal Vector3 / CFrame shim (just what Convert's cf / assetCF / cameraCF need) --------------------------
local V = {}
V.__index = function(v, k)
	if k == "X" then
		return v.x
	elseif k == "Y" then
		return v.y
	elseif k == "Z" then
		return v.z
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
function V.Dot(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z
end
local Vector3 = { new = V.new, zero = V.new(0, 0, 0) }

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
local ID = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function quatMatrix(x, y, z, w)
	return {
		1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
		2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
		2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y),
	}
end
local CFrame = {
	new = function(a, b, c, qx, qy, qz, qw)
		if a == nil then
			return cf(0, 0, 0, ID)
		end
		if qw ~= nil then
			local n = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
			return cf(a, b, c, quatMatrix(qx / n, qy / n, qz / n, qw / n))
		end
		return cf(a, b, c, ID)
	end,
	Angles = function(a, b, c)
		local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
		local rx = { 1, 0, 0, 0, ca, -sa, 0, sa, ca }
		local ry = { cb, 0, sb, 0, 1, 0, -sb, 0, cb }
		local rz = { cc, -sc, 0, sc, cc, 0, 0, 0, 1 }
		return cf(0, 0, 0, mmul(rx, mmul(ry, rz)))
	end,
}
CFrame.identity = CFrame.new()

local Timeline = require("../../src/IntroCutscene/Timeline")
local Convert = require("../../src/IntroCutscene/Convert")
Convert.useMath(CFrame, Vector3)
local data = require("../../src/IntroCutscene/IntroData")
local fixture = require("./intro_parity")

-- harness ---------------------------------------------------------------------------------------------
local TOL = {
	pos = 0.05,
	camPos = 0.02,
	rot = 0.5,
	scale = 0.01,
	channel = 0.01,
	joint = 0.75,
	rootLoc = 0.05,
	convention = 0.05,
}

local failures, checks = 0, 0
local worst = {} -- kind -> { err, where }
local counts = {} -- kind -> number of comparisons
local function fail(msg)
	failures += 1
	print("FAIL " .. msg)
end
local function measure(kind, err, tol, where)
	checks += 1
	counts[kind] = (counts[kind] or 0) + 1
	local w = worst[kind]
	if not w or err > w.err then
		worst[kind] = { err = err, where = where, tol = tol }
	end
	if err ~= err or err > tol then
		fail(string.format("%s %s: error %.4f > %.4f", kind, where, err, tol))
	end
end

local function dist(a, b)
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end
-- angle (degrees) between two unit quaternions, sign-agnostic
local function quatAngle(a, b)
	local la = math.sqrt(a[1] ^ 2 + a[2] ^ 2 + a[3] ^ 2 + a[4] ^ 2)
	local lb = math.sqrt(b[1] ^ 2 + b[2] ^ 2 + b[3] ^ 2 + b[4] ^ 2)
	local d = math.abs(a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]) / (la * lb)
	return math.deg(2 * math.acos(math.min(1, d)))
end
local function vecAngle(a, b)
	local d = a:Dot(b) / math.sqrt(a:Dot(a) * b:Dot(b))
	return math.deg(math.acos(math.clamp(d, -1, 1)))
end

-- the fixture must belong to this IntroData --------------------------------------------------------------
local tl = Timeline.new(data)
do
	local fd = fixture.data
	local stale = {}
	if math.abs(fd.duration - data.duration) > 1e-6 then
		table.insert(stale, string.format("duration %.3f vs %.3f", fd.duration, data.duration))
	end
	for name, ft in pairs(fd.tracks) do
		local d = data.tracks[name]
		if not d then
			table.insert(stale, "track " .. name .. " missing")
		elseif d.n ~= ft.n or math.abs(d.t0 - ft.t0) > 1e-6 or d.rate ~= ft.rate then
			table.insert(stale, string.format("track %s t0/n/rate %.3f/%d/%d vs %.3f/%d/%d", name, d.t0, d.n, d.rate, ft.t0, ft.n, ft.rate))
		end
	end
	for name in pairs(data.tracks) do
		if not fd.tracks[name] then
			table.insert(stale, "track " .. name .. " not in the fixture")
		end
	end
	local fc, dc = fd.character, data.character
	if (fc == nil) ~= (dc == nil) or (fc and (fc.n ~= dc.n or math.abs(fc.t0 - dc.t0) > 1e-6)) then
		table.insert(stale, "character range")
	end
	if #stale > 0 then
		local shown = table.concat(stale, "; ", 1, math.min(#stale, 3))
		if #stale > 3 then
			shown ..= string.format("; and %d more", #stale - 3)
		end
		print("FAIL the parity fixture does not belong to src/IntroCutscene/IntroData.luau (" .. shown
			.. "). Export both together: tools/blender/intro/export_intro.py with a parity path.")
		error("stale parity fixture")
	end
end

-- a cut inside the sample interval of t on this sampler's grid -> skip
local function atCut(s, t)
	local fi = (t - s.t0) * s.rate
	if fi <= 0 or fi >= s.n - 1 then
		return false
	end
	local i = math.floor(fi)
	return tl:cutBetween(s.t0 + i / s.rate, s.t0 + (i + 1) / s.rate) ~= nil
end

-- The runtime interpolates 30 Hz samples (Catmull-Rom / slerp / linear) while Blender evaluates the
-- exact sub-frame value. During very fast motion (a spinning sword, a whip-fast arm swing, an FOV
-- punch) the two drift apart by a small share of the motion between the two samples around t, which
-- is invisible at 60 fps. So each tolerance grows with that motion; a wrong conversion still fails,
-- because its error is a large share of the motion (or a constant offset when nothing moves).
local MOTION_SHARE = 0.12

local function bracket(s, t)
	local i = math.clamp(math.floor((t - s.t0) * s.rate), 0, math.max(s.n - 2, 0))
	return s.t0 + i / s.rate, s.t0 + (i + 1) / s.rate
end
local function copy3(v)
	return { v[1], v[2], v[3] }
end
local function copy4(q)
	return { q[1], q[2], q[3], q[4] }
end
local function copyMap(m, f)
	local out = {}
	for k, v in pairs(m) do
		out[k] = f(v)
	end
	return out
end
local function ident(v)
	return v
end
local function trackState(tr, t)
	local s = tr:sample(t)
	return { pos = copy3(s.pos), rot = copy4(s.rot), scale = s.scale, channels = copyMap(s.channels, ident) }
end
local function charState(t)
	local c = tl:character(t)
	return {
		pos = copy3(c.root.pos),
		rot = copy4(c.root.rot),
		rootLoc = copy3(c.rootLoc),
		channels = copyMap(c.channels, ident),
		joints = copyMap(c.joints, copy4),
	}
end
local function allow(tol, motion)
	return math.max(tol, MOTION_SHARE * (motion or 0))
end

local skipped, heldSkipped = 0, 0
local idCF = CFrame.new()
for _, e in ipairs(fixture.samples) do
	local t = e.t
	local where = string.format("%s t=%.4f", e.track, t)
	-- values Blender holds over this frame interval (CONSTANT keys / constraint switches not at a
	-- cut; the exporter warns about real jumps): the runtime blends them, so they are not compared
	local held = {}
	for _, key in ipairs(e.held or {}) do
		held[key] = true
	end
	local function check(key, kind, err, tol)
		if held[key] then
			heldSkipped += 1
		else
			measure(kind, err, tol, where)
		end
	end
	if e.track == "character" then
		local ct = tl:characterTrack()
		if atCut(ct, t) then
			skipped += 1
		else
			local ta, tb = bracket(ct, t)
			local a, b = charState(ta), charState(tb)
			local c = tl:character(t)
			check("pos", "character pos", dist(c.root.pos, e.pos), allow(TOL.pos, dist(a.pos, b.pos)))
			check("rot", "character rot", quatAngle(c.root.rot, e.rot), allow(TOL.rot, quatAngle(a.rot, b.rot)))
			check("rootLoc", "character rootLoc", dist(c.rootLoc, e.rootLoc), allow(TOL.rootLoc, dist(a.rootLoc, b.rootLoc)))
			for name, v in pairs(e.channels) do
				local got = c.channels[name]
				if got == nil then
					fail(where .. ": no character channel " .. name)
				else
					local motion = a.channels[name] and b.channels[name] and math.abs(a.channels[name] - b.channels[name])
					check("." .. name, "character ." .. name, math.abs(got - v), allow(TOL.channel, motion))
				end
			end
			for name, q in pairs(e.joints) do
				local motion = quatAngle(a.joints[name], b.joints[name])
				check("joint " .. name, "joint " .. name, quatAngle(c.joints[name], q), allow(TOL.joint, motion))
			end
		end
	else
		local tr = tl:track(e.track)
		if not tr then
			fail(where .. ": no such track in IntroData")
		elseif atCut(tr, t) then
			skipped += 1
		else
			local ta, tb = bracket(tr, t)
			local a, b = trackState(tr, ta), trackState(tr, tb)
			local s = tr:sample(t)
			local cam = e.track == "Camera"
			check("pos", e.track .. " pos", dist(s.pos, e.pos), allow(cam and TOL.camPos or TOL.pos, dist(a.pos, b.pos)))
			check("rot", e.track .. " rot", quatAngle(s.rot, e.rot), allow(TOL.rot, quatAngle(a.rot, b.rot)))
			if e.scale then
				check("scale", e.track .. " scale", math.abs(s.scale - e.scale), allow(TOL.scale, math.abs(a.scale - b.scale)))
			end
			for name, v in pairs(e.channels) do
				local got = s.channels[name]
				if got == nil then
					fail(where .. ": no channel " .. name)
				else
					local motion = a.channels[name] and b.channels[name] and math.abs(a.channels[name] - b.channels[name])
					check("." .. name, e.track .. " ." .. name, math.abs(got - v), allow(TOL.channel, motion))
				end
			end
			-- conventions: Blender directions vs the Roblox CFrames Convert builds from the samples
			if e.look then
				local ccf = Convert.cameraCF(idCF, e.pos, e.rot)
				measure("convention camera look", vecAngle(ccf.LookVector, Convert.posOf(e.look)), TOL.convention, where)
				measure("convention camera up", vecAngle(ccf.UpVector, Convert.posOf(e.up)), TOL.convention, where)
			end
			if e.blade then
				local acf = Convert.assetCF(idCF, e.pos, e.rot)
				measure("convention sword blade", vecAngle(acf.UpVector, Convert.posOf(e.blade)), TOL.convention, where)
			end
		end
	end
end

-- report ----------------------------------------------------------------------------------------------
local kinds = {}
for kind in pairs(worst) do
	table.insert(kinds, kind)
end
table.sort(kinds)
print(string.format("%-28s %6s %10s %8s  %s", "kind", "count", "worst", "limit", "where"))
for _, kind in ipairs(kinds) do
	local w = worst[kind]
	print(string.format("%-28s %6d %10.5f %8.3f  %s", kind, counts[kind], w.err, w.tol, w.where))
end
print(
	string.format(
		"%d fixture entries, %d comparisons, %d skipped at cuts, %d held in Blender (not compared), %d failures",
		#fixture.samples,
		checks,
		skipped,
		heldSkipped,
		failures
	)
)
if failures > 0 then
	error(failures .. " parity failures")
end
print("PASS")
