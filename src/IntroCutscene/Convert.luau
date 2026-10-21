--[=[
	Convert
	Blender -> Roblox math of the intro (docs/intro/DESIGN.md §2, §4.2, §4.3).

	Blender is Z-up with the character facing +Y; Roblox is Y-up facing -Z.
	R(x, y, z) = (x, z, -y), i.e. C = [[1,0,0],[0,0,1],[0,-1,0]] and a Blender
	rotation Rbl becomes C·Rbl·Cᵀ. For a quaternion (w, x, y, z) that is simply
	(w, x, z, -y): conjugating by a proper rotation rotates the quaternion's axis.

	p and q below are the arrays Timeline samples return: p = { x, y, z },
	q = { w, x, y, z } (Blender world space of a stage).

	    Convert.pos(x, y, z)            -> Vector3       R(p), stage-local
	    Convert.posOf(p)                -> Vector3       same for an array
	    Convert.rotFromQuat(w, x, y, z) -> CFrame        rotation only, C·R·Cᵀ
	    Convert.cf(origin, p, q)        -> CFrame        origin * CFrame.new(R(p)) * Rrbx
	                                                     (objects whose local axes are Blender's
	                                                     own, e.g. CharacterRoot = the HRP)
	    Convert.assetCF(origin, p, q)   -> CFrame        cf(...) * CFrame.Angles(0, pi, 0): where an
	                                                     IntroAssets model's pivot goes (assets face -Y)
	    Convert.cameraCF(origin, p, q)  -> CFrame        cf(...) * CFrame.Angles(-pi/2, 0, 0): a Blender
	                                                     camera looks down its local -Z with +Y up, which
	                                                     is already Roblox's camera convention, so only the
	                                                     world part is converted
	    Convert.jointCF(q, loc?)        -> CFrame        Motor6D.Transform from a joint-space quaternion
	                                                     (+ Root location); no axis change (§4.2)
	    Convert.fromBlender(x, y, z)    -> Vector3       asset-local offset (-x, z, y) (asset library rule)
	    Convert.stageOrigin(position, towardHub) -> CFrame  world origin: Blender +Y points along towardHub
	    Convert.grip(handCF)            -> CFrame        sword pivot in the right hand (§4.3)
	    Convert.selfCheck()             -> ok, message   numeric check of all of the above
	    Convert.useMath(CFrame, Vector3) plain-Luau tests only: use a CFrame/Vector3 shim
]=]

local Convert = {}

-- Roblox's CFrame / Vector3 (plain-Luau tests hand in a shim with Convert.useMath)
local CF, V3 = CFrame, Vector3
local ASSET_TURN, CAMERA_FIX, GRIP

local function setup()
	ASSET_TURN = CF.Angles(0, math.pi, 0)
	CAMERA_FIX = CF.Angles(-math.pi / 2, 0, 0)
	GRIP = CF.new(0, -0.15, 0) * CF.Angles(-math.pi / 2, 0, 0)
	Convert.ASSET_TURN = ASSET_TURN
	Convert.CAMERA_FIX = CAMERA_FIX
	Convert.GRIP = GRIP
end

-- Tests outside Roblox: use these CFrame / Vector3 implementations.
function Convert.useMath(cframe, vector3)
	CF, V3 = cframe, vector3
	setup()
end

if CF then
	setup()
end

function Convert.pos(x, y, z)
	return V3.new(x, z, -y)
end

function Convert.posOf(p)
	return V3.new(p[1], p[3], -p[2])
end

function Convert.rotFromQuat(w, x, y, z)
	return CF.new(0, 0, 0, x, z, -y, w)
end

-- Stage-local CFrame (no origin) of a Blender position + quaternion.
function Convert.localCF(p, q)
	return CF.new(p[1], p[3], -p[2], q[2], q[4], -q[3], q[1])
end

function Convert.cf(origin, p, q)
	return origin * CF.new(p[1], p[3], -p[2], q[2], q[4], -q[3], q[1])
end

function Convert.assetCF(origin, p, q)
	return origin * CF.new(p[1], p[3], -p[2], q[2], q[4], -q[3], q[1]) * ASSET_TURN
end

function Convert.cameraCF(origin, p, q)
	return origin * CF.new(p[1], p[3], -p[2], q[2], q[4], -q[3], q[1]) * CAMERA_FIX
end

function Convert.jointCF(q, loc)
	if loc then
		return CF.new(loc[1], loc[2], loc[3], q[2], q[3], q[4], q[1])
	end
	return CF.new(0, 0, 0, q[2], q[3], q[4], q[1])
end

function Convert.fromBlender(x, y, z)
	return V3.new(-x, z, y)
end

-- Origin CFrame at `position` whose LookVector (= Blender +Y) points along towardHub (flattened).
function Convert.stageOrigin(position, towardHub)
	local flat = towardHub and V3.new(towardHub.X, 0, towardHub.Z)
	if not flat or flat.Magnitude < 1e-3 then
		return CF.new(position)
	end
	return CF.lookAt(position, position + flat.Unit)
end

function Convert.grip(handCF)
	return handCF * GRIP
end

-- Numeric self-check (runs anywhere CFrame exists; the unit test runs it against a shim).
function Convert.selfCheck()
	local problems = {}
	local function near(a, b, what)
		if (a - b).Magnitude > 1e-4 then
			table.insert(problems, string.format("%s: got (%.4f, %.4f, %.4f) want (%.4f, %.4f, %.4f)", what, a.X, a.Y, a.Z, b.X, b.Y, b.Z))
		end
	end
	local id = CF.new()
	-- positions: Blender +Y (forward) -> Roblox -Z, +Z (up) -> +Y
	near(Convert.pos(1, 2, 3), V3.new(1, 3, -2), "pos")
	-- an unrotated object faces Blender +Y = Roblox LookVector (-Z)
	local q0 = { 1, 0, 0, 0 }
	near(Convert.cf(id, { 0, 0, 0 }, q0).LookVector, V3.new(0, 0, -1), "identity look")
	-- 90 degrees about Blender +Z (counter-clockwise seen from above): +Y turns to -X
	local h = math.sqrt(0.5)
	local qz = { h, 0, 0, h }
	local cfz = Convert.cf(id, { 0, 0, 0 }, qz)
	near(cfz:VectorToWorldSpace(V3.new(0, 0, -1)), V3.new(-1, 0, 0), "yaw 90 forward")
	near(cfz:VectorToWorldSpace(V3.new(0, 1, 0)), V3.new(0, 1, 0), "yaw 90 up")
	-- 90 degrees about Blender +X: +Y (forward) turns to +Z (up)
	local qx = { h, h, 0, 0 }
	near(Convert.cf(id, { 0, 0, 0 }, qx).LookVector, V3.new(0, 1, 0), "pitch 90 forward")
	-- origin and offset compose
	local origin = CF.new(10, 20, 30) * CF.Angles(0, math.pi / 2, 0)
	near(Convert.cf(origin, { 0, 5, 0 }, q0).Position, origin * V3.new(0, 0, -5), "origin offset")
	-- assets: asset-local fromBlender offsets land where Blender has them
	local acf = Convert.assetCF(id, { 0, 0, 0 }, qz)
	local blenderPoint = V3.new(0, -1, 0) -- the asset's front (Blender -Y) rotated by qz -> Blender +X
	near(acf * Convert.fromBlender(blenderPoint.X, blenderPoint.Y, blenderPoint.Z), Convert.pos(1, 0, 0), "asset front")
	near(acf.LookVector, Convert.pos(1, 0, 0), "asset look = its front")
	-- camera: an unrotated Blender camera looks straight down
	near(Convert.cameraCF(id, { 0, 0, 0 }, q0).LookVector, V3.new(0, -1, 0), "camera identity look")
	near(Convert.cameraCF(id, { 0, 0, 0 }, q0).UpVector, V3.new(0, 0, -1), "camera identity up")
	-- camera rotated 90 degrees about Blender +X looks along Blender +Y = Roblox -Z, up Blender +Z
	near(Convert.cameraCF(id, { 0, 0, 0 }, qx).LookVector, V3.new(0, 0, -1), "camera level look")
	near(Convert.cameraCF(id, { 0, 0, 0 }, qx).UpVector, V3.new(0, 1, 0), "camera level up")
	-- joints: same numbers, no axis change (90 degrees about joint X tips +Y up to +Z back)
	near(Convert.jointCF(qx):VectorToWorldSpace(V3.new(0, 1, 0)), V3.new(0, 0, 1), "joint x")
	near(Convert.jointCF(q0, { 1, 2, 3 }).Position, V3.new(1, 2, 3), "joint loc")
	-- grip: the blade (asset +Y) points along the hand's -Z
	near(Convert.grip(id):VectorToWorldSpace(V3.new(0, 1, 0)), V3.new(0, 0, -1), "grip blade")
	near(Convert.grip(id).Position, V3.new(0, -0.15, 0), "grip offset")
	-- stage origin: LookVector toward the hub
	local o = Convert.stageOrigin(V3.new(100, 5, 0), V3.new(-100, 0, 0))
	near(o.LookVector, V3.new(-1, 0, 0), "stage origin look")
	near(Convert.cf(o, { 0, 10, 0 }, q0).Position, V3.new(90, 5, 0), "stage origin +Y toward hub")
	if #problems > 0 then
		return false, table.concat(problems, "; ")
	end
	return true, "ok"
end

return Convert
