--[[
	Timeline
	Samples the baked tracks of IntroData at any time t (docs/intro/DESIGN.md §8).
	Pure Luau: no Roblox types, plain numbers in Blender coordinates. Convert
	turns samples into CFrames.

	    local tl = Timeline.new(IntroData)
	    local cam = tl:track("Camera")            -- Track or nil
	    local s = cam:sample(t)                    -- reused table, copy what you keep
	    s.pos      -- { x, y, z }     Blender stage coordinates (Catmull-Rom)
	    s.rot      -- { w, x, y, z }  unit quaternion, Blender world rotation (slerp)
	    s.scale    -- number (1 when the track has no scale)
	    s.channels -- { name = value } (linear; step for visible/held/is*)
	    s.t        -- the time sampled
	    cam:channel("fov", t)                      -- one channel, no table writes
	    cam:has("fov"), cam.stage, cam.t0, cam.t1 -- first / last sample time

	    local c = tl:character(t)                  -- nil when the data has no character
	    c.root.pos, c.root.rot                     -- HumanoidRootPart (like a track sample)
	    c.joints.Waist                             -- { w, x, y, z } joint-space quaternion (§4.2)
	    c.rootLoc                                  -- { x, y, z } Root bone location (joint space)
	    c.channels.visible, c.channels.form
	    tl:characterTrack()                        -- the sampler itself (t0, t1, n, ...)

	    tl:stageAt(t)            -> "space" | "world"   (world from stageSwitch on)
	    tl:cutBetween(a, b)      -> first cut time c with a < c <= b, or nil
	    tl.markers               -- { { t, name, kind, args = {...} } } sorted by t
	    tl:markersOf(kind)       -> list of those markers
	    tl:firstMarker(kind, arg1?) -> marker or nil
	    local cur = tl:cursor()
	    cur:advance(t, function(m) ... end)   -- fires every marker with m.t <= t once, in order
	    Timeline.parseMarker("shake:0.4:1.6") -> "shake", { 0.4, 1.6 }

	Sampling rules: i = (t - t0) * rate, clamped to [0, n - 1]; positions use a
	centripetal Catmull-Rom spline over samples i-1 .. i+2 (a neighbour missing
	at a track end or a cut is extrapolated from the samples on t's side),
	rotations slerp between i and i+1 (shortest arc), scalars
	are linear, step channels take sample floor(i). When a cut lies in
	(time(i), time(i+1)] the sample on t's side of the cut is used as is, and
	the spline never reaches across a cut for its outer neighbours either.

	Every sample call reuses the same output tables: no allocation per frame.
]]

local Timeline = {}
Timeline.__index = Timeline

local EPS = 1e-6
local floor = math.floor
local sqrt = math.sqrt
local acos = math.acos
local sin = math.sin

local JOINT_NAMES = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}
Timeline.JOINT_NAMES = JOINT_NAMES

-- Channels that hold their value until the next sample (DESIGN §8).
local function isStep(name)
	return name == "visible" or name == "held" or string.sub(name, 1, 2) == "is"
end
Timeline.isStep = isStep

-- "kind:arg1:arg2" -> kind, { args } (numbers converted)
function Timeline.parseMarker(name)
	local parts = string.split(name, ":")
	local kind = parts[1] or ""
	local args = {}
	for k = 2, #parts do
		local v = parts[k]
		args[k - 1] = tonumber(v) or v
	end
	return kind, args
end

-- first cut c with a < c <= b (both with a small tolerance), or nil
local function cutIn(cuts, a, b)
	for k = 1, #cuts do
		local c = cuts[k]
		if c > a + EPS and c <= b + EPS then
			return c
		end
		if c > b + EPS then
			return nil
		end
	end
	return nil
end

--[[ Locate t on a sampler's grid. Returns
	i      lower sample index (0-based)
	f      fraction towards i + 1 (0 when held by a clamp or a cut)
	hasP   sample i - 1 may be used as the spline's first neighbour
	hasN   sample i + 2 may be used as the spline's last neighbour
]]
local function locate(s, t)
	local n = s.n
	if n <= 1 then
		return 0, 0, false, false
	end
	local rate, t0 = s.rate, s.t0
	local fi = (t - t0) * rate
	if fi <= 0 then
		return 0, 0, false, false
	end
	if fi >= n - 1 then
		return n - 1, 0, false, false
	end
	local i = floor(fi)
	local f = fi - i
	if f > 1 - 1e-7 then
		i += 1
		f = 0
		if i >= n - 1 then
			return n - 1, 0, false, false
		end
	end
	local cuts = s.cuts
	if #cuts > 0 then
		local ta = t0 + i / rate
		local tb = t0 + (i + 1) / rate
		local c = cutIn(cuts, ta, tb)
		if c then
			if t < c - EPS then
				return i, 0, false, false
			end
			return i + 1, 0, false, false
		end
		local hasP = i >= 1 and cutIn(cuts, t0 + (i - 1) / rate, ta) == nil
		local hasN = i + 2 <= n - 1 and cutIn(cuts, tb, t0 + (i + 2) / rate) == nil
		return i, f, hasP, hasN
	end
	return i, f, i >= 1, i + 2 <= n - 1
end
Timeline._locate = locate

-- Centripetal Catmull-Rom of the flat xyz array P between samples i and i + 1, into out.
local function splinePos(P: { number }, i: number, f: number, hasP: boolean, hasN: boolean, out: { number })
	local b = i * 3
	local bx, by, bz = P[b + 1], P[b + 2], P[b + 3]
	if f == 0 then
		out[1], out[2], out[3] = bx, by, bz
		return
	end
	local cx, cy, cz = P[b + 4], P[b + 5], P[b + 6]
	-- a missing outer neighbour (track end, cut) is extrapolated: quadratically through the
	-- three samples on this side when there are three, else mirrored
	local ax, ay, az, dx, dy, dz
	if hasP then
		ax, ay, az = P[b - 2], P[b - 1], P[b]
	elseif hasN then
		ax, ay, az = 3 * bx - 3 * cx + P[b + 7], 3 * by - 3 * cy + P[b + 8], 3 * bz - 3 * cz + P[b + 9]
	else
		ax, ay, az = 2 * bx - cx, 2 * by - cy, 2 * bz - cz
	end
	if hasN then
		dx, dy, dz = P[b + 7], P[b + 8], P[b + 9]
	elseif hasP then
		dx, dy, dz = 3 * cx - 3 * bx + ax, 3 * cy - 3 * by + ay, 3 * cz - 3 * bz + az
	else
		dx, dy, dz = 2 * cx - bx, 2 * cy - by, 2 * cz - bz
	end
	-- knot intervals: |segment| ^ 0.5
	local d12 = sqrt(sqrt((cx - bx) ^ 2 + (cy - by) ^ 2 + (cz - bz) ^ 2))
	if d12 < 1e-4 then
		out[1], out[2], out[3] = bx + (cx - bx) * f, by + (cy - by) * f, bz + (cz - bz) * f
		return
	end
	local d01 = sqrt(sqrt((bx - ax) ^ 2 + (by - ay) ^ 2 + (bz - az) ^ 2))
	local d23 = sqrt(sqrt((dx - cx) ^ 2 + (dy - cy) ^ 2 + (dz - cz) ^ 2))
	if d01 < 1e-4 then
		d01 = d12
	end
	if d23 < 1e-4 then
		d23 = d12
	end
	local t1 = d01
	local t2 = t1 + d12
	local t3 = t2 + d23
	local u = t1 + f * d12
	-- Barry-Goldman pyramid, expanded into four weights
	local a1a, a1b = (t1 - u) / t1, u / t1
	local a2b, a2c = (t2 - u) / d12, (u - t1) / d12
	local a3c, a3d = (t3 - u) / d23, (u - t2) / d23
	local b1, b1p = (t2 - u) / t2, u / t2
	local b2, b2p = (t3 - u) / (t3 - t1), (u - t1) / (t3 - t1)
	local c, cp = (t2 - u) / d12, (u - t1) / d12
	local wA = c * b1 * a1a
	local wB = c * (b1 * a1b + b1p * a2b) + cp * b2 * a2b
	local wC = c * b1p * a2c + cp * (b2 * a2c + b2p * a3c)
	local wD = cp * b2p * a3d
	out[1] = wA * ax + wB * bx + wC * cx + wD * dx
	out[2] = wA * ay + wB * by + wC * cy + wD * dy
	out[3] = wA * az + wB * bz + wC * cz + wD * dz
end

-- Linear interpolation of the flat xyz array P (used for the Root bone location).
local function lerpPos(P: { number }, i: number, f: number, out: { number })
	local b = i * 3
	if f == 0 then
		out[1], out[2], out[3] = P[b + 1], P[b + 2], P[b + 3]
		return
	end
	out[1] = P[b + 1] + (P[b + 4] - P[b + 1]) * f
	out[2] = P[b + 2] + (P[b + 5] - P[b + 2]) * f
	out[3] = P[b + 3] + (P[b + 6] - P[b + 3]) * f
end

-- Shortest-arc slerp of the flat wxyz array R between samples i and i + 1, normalised, into out.
local function slerpRot(R: { number }, i: number, f: number, out: { number })
	local b = i * 4
	local w1, x1, y1, z1 = R[b + 1], R[b + 2], R[b + 3], R[b + 4]
	local w, x, y, z
	if f == 0 then
		w, x, y, z = w1, x1, y1, z1
	else
		local w2, x2, y2, z2 = R[b + 5], R[b + 6], R[b + 7], R[b + 8]
		local dot = w1 * w2 + x1 * x2 + y1 * y2 + z1 * z2
		if dot < 0 then
			w2, x2, y2, z2 = -w2, -x2, -y2, -z2
			dot = -dot
		end
		local k1, k2
		if dot > 0.9995 then
			k1, k2 = 1 - f, f
		else
			local theta = acos(dot)
			local s = sin(theta)
			k1 = sin((1 - f) * theta) / s
			k2 = sin(f * theta) / s
		end
		w = w1 * k1 + w2 * k2
		x = x1 * k1 + x2 * k2
		y = y1 * k1 + y2 * k2
		z = z1 * k1 + z2 * k2
	end
	local len = sqrt(w * w + x * x + y * y + z * z)
	if len < 1e-9 then
		out[1], out[2], out[3], out[4] = 1, 0, 0, 0
		return
	end
	out[1], out[2], out[3], out[4] = w / len, x / len, y / len, z / len
end

local function scalarAt(V: { number }, i: number, f: number, step: boolean?): number
	local a = V[i + 1]
	if step or f == 0 then
		return a
	end
	return a + (V[i + 2] - a) * f
end

local function channelSetup(sampler, channels)
	sampler.channelData = channels or {}
	sampler.stepChannel = {}
	sampler.channelNames = {}
	for name in pairs(sampler.channelData) do
		table.insert(sampler.channelNames, name)
		sampler.stepChannel[name] = isStep(name)
	end
	table.sort(sampler.channelNames)
end

local function fillChannels(sampler, i, f, out)
	local data, step = sampler.channelData, sampler.stepChannel
	local names = sampler.channelNames
	for k = 1, #names do
		local name = names[k]
		out[name] = scalarAt(data[name], i, f, step[name])
	end
end

local function sampleCount(d, fallback)
	if d.n then
		return d.n
	end
	if d.pos then
		return #d.pos // 3
	end
	return fallback
end

-- Track ---------------------------------------------------------------------------------------------
local Track = {}
Track.__index = Track
Timeline.Track = Track

function Track.new(name, d, fps, cuts)
	local self = setmetatable({}, Track)
	self.name = name
	self.stage = d.stage or "world"
	self.rate = d.rate or fps
	self.t0 = d.t0 or 0
	self.n = sampleCount(d, 1)
	self.t1 = self.t0 + (self.n - 1) / self.rate
	self.posData = d.pos
	self.rotData = d.rot
	self.scaleData = d.scale
	self.cuts = cuts
	channelSetup(self, d.channels)
	self.out = { pos = { 0, 0, 0 }, rot = { 1, 0, 0, 0 }, scale = 1, channels = {}, t = 0 }
	return self
end

function Track:has(channel)
	return self.channelData[channel] ~= nil
end

function Track:sample(t)
	local out = self.out
	local i, f, hasP, hasN = locate(self, t)
	out.t = t
	if self.posData then
		splinePos(self.posData, i, f, hasP, hasN, out.pos)
	end
	if self.rotData then
		slerpRot(self.rotData, i, f, out.rot)
	end
	out.scale = self.scaleData and scalarAt(self.scaleData, i, f, false) or 1
	fillChannels(self, i, f, out.channels)
	return out
end

-- One channel's value at t (nil if the track has no such channel).
function Track:channel(name, t)
	local data = self.channelData[name]
	if not data then
		return nil
	end
	local i, f = locate(self, t)
	return scalarAt(data, i, f, self.stepChannel[name])
end

-- Character -----------------------------------------------------------------------------------------
local Character = {}
Character.__index = Character
Timeline.Character = Character

function Character.new(d, fps, cuts)
	local self = setmetatable({}, Character)
	self.rate = d.rate or fps
	self.t0 = d.t0 or 0
	local root = d.root or {}
	self.n = d.n or (root.pos and #root.pos // 3) or 1
	self.t1 = self.t0 + (self.n - 1) / self.rate
	self.posData = root.pos
	self.rotData = root.rot
	self.rootLocData = d.rootLoc
	self.cuts = cuts
	self.jointData = d.joints or {}
	self.jointNames = {}
	for _, name in ipairs(JOINT_NAMES) do
		if self.jointData[name] then
			table.insert(self.jointNames, name)
		end
	end
	for name in pairs(self.jointData) do
		if not table.find(self.jointNames, name) then
			table.insert(self.jointNames, name)
		end
	end
	channelSetup(self, d.channels)
	local joints = {}
	for _, name in ipairs(self.jointNames) do
		joints[name] = { 1, 0, 0, 0 }
	end
	self.out = {
		root = { pos = { 0, 0, 0 }, rot = { 1, 0, 0, 0 } },
		joints = joints,
		rootLoc = { 0, 0, 0 },
		channels = {},
		t = 0,
		t0 = self.t0,
		t1 = self.t1,
	}
	return self
end

function Character:sample(t)
	local out = self.out
	local i, f, hasP, hasN = locate(self, t)
	out.t = t
	if self.posData then
		splinePos(self.posData, i, f, hasP, hasN, out.root.pos)
	end
	if self.rotData then
		slerpRot(self.rotData, i, f, out.root.rot)
	end
	local names, data, joints = self.jointNames, self.jointData, out.joints
	for k = 1, #names do
		local name = names[k]
		slerpRot(data[name], i, f, joints[name])
	end
	if self.rootLocData then
		lerpPos(self.rootLocData, i, f, out.rootLoc)
	end
	fillChannels(self, i, f, out.channels)
	return out
end

function Character:channel(name, t)
	local data = self.channelData[name]
	if not data then
		return nil
	end
	local i, f = locate(self, t)
	return scalarAt(data, i, f, self.stepChannel[name])
end

-- Marker cursor -------------------------------------------------------------------------------------
local Cursor = {}
Cursor.__index = Cursor

-- Fire fn(marker) for every marker with marker.t <= t not fired yet, in order. Returns the count.
function Cursor:advance(t, fn)
	local markers = self.markers
	local count = 0
	while self.index <= #markers do
		local m = markers[self.index]
		if m.t > t + EPS then
			break
		end
		self.index += 1 -- before fn: a marker never fires twice, even if fn errors
		count += 1
		fn(m)
	end
	return count
end

-- The next marker that has not fired, or nil.
function Cursor:peek()
	return self.markers[self.index]
end

-- Rewind so that the next advance fires markers after time t (nil = from the start).
function Cursor:reset(t)
	self.index = 1
	if t then
		while self.index <= #self.markers and self.markers[self.index].t <= t + EPS do
			self.index += 1
		end
	end
end

-- Timeline ------------------------------------------------------------------------------------------
function Timeline.new(data)
	assert(type(data) == "table", "Timeline.new needs the IntroData table")
	local self = setmetatable({}, Timeline)
	self.data = data
	self.fps = data.fps or 30
	self.duration = data.duration or 0
	self.stageSwitch = data.stageSwitch or math.huge
	local cuts = {}
	for _, c in ipairs(data.cuts or {}) do
		table.insert(cuts, c)
	end
	table.sort(cuts)
	self.cuts = cuts
	local markers = {}
	for k, m in ipairs(data.markers or {}) do
		local kind, args = Timeline.parseMarker(m.name)
		table.insert(markers, { t = m.t, name = m.name, kind = kind, args = args, order = k })
	end
	table.sort(markers, function(a, b)
		if a.t ~= b.t then
			return a.t < b.t
		end
		return a.order < b.order
	end)
	self.markers = markers
	self.tracks = {}
	for name, d in pairs(data.tracks or {}) do
		self.tracks[name] = Track.new(name, d, self.fps, cuts)
	end
	if data.character then
		self.characterSampler = Character.new(data.character, self.fps, cuts)
	end
	return self
end

function Timeline:track(name)
	return self.tracks[name]
end

function Timeline:trackNames()
	local names = {}
	for name in pairs(self.tracks) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Timeline:characterTrack()
	return self.characterSampler
end

function Timeline:character(t)
	local c = self.characterSampler
	return c and c:sample(t) or nil
end

function Timeline:stageAt(t)
	if t >= self.stageSwitch - EPS then
		return "world"
	end
	return "space"
end

function Timeline:cutBetween(a, b)
	return cutIn(self.cuts, a, b)
end

function Timeline:markersOf(kind)
	local list = {}
	for _, m in ipairs(self.markers) do
		if m.kind == kind then
			table.insert(list, m)
		end
	end
	return list
end

function Timeline:firstMarker(kind, arg1)
	for _, m in ipairs(self.markers) do
		if m.kind == kind and (arg1 == nil or m.args[1] == arg1) then
			return m
		end
	end
	return nil
end

function Timeline:cursor()
	return setmetatable({ markers = self.markers, index = 1 }, Cursor)
end

return Timeline
