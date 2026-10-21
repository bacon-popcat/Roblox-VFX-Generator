--!nocheck
-- A small Roblox runtime for running VFX effect modules outside Studio, in the plain Luau
-- CLI. It is not a renderer: it type-checks every property an effect sets (unknown
-- properties, wrong types, bad enum items and malformed sequences error like Studio
-- does), runs the effect on a virtual 60 fps clock, and records what it emitted so the
-- driver can check Linger and the budget. run.mjs bundles this file, the modules and a
-- driver into one chunk.

local NOW = 0 -- virtual seconds
local FRAME = 1 / 60

--------------------------------------------------------------------------------
-- typeof

local realTypeof = typeof
local function rtype(value)
	local mt = getmetatable(value)
	if type(mt) == "table" and rawget(mt, "__type") then
		return mt.__type
	end
	return realTypeof(value)
end
typeof = rtype

local function fail(message)
	error(message, 3)
end

--------------------------------------------------------------------------------
-- Vector3 / Vector2

local V3 = { __type = "Vector3" }
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
local function isV3(v)
	return getmetatable(v) == V3
end
V3.__index = function(v, key)
	if key == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif key == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return v3(0 / 0, 0 / 0, 0 / 0)
		end
		return v3(v.X / m, v.Y / m, v.Z / m)
	end
	local method = rawget(V3, key)
	if method then
		return method
	end
	fail(tostring(key) .. " is not a valid member of Vector3")
end
V3.__add = function(a, b)
	if not isV3(a) or not isV3(b) then
		fail("invalid argument to Vector3 +")
	end
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	if not isV3(a) or not isV3(b) then
		fail("invalid argument to Vector3 -")
	end
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	elseif isV3(a) and isV3(b) then
		return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end
	fail("invalid argument to Vector3 *")
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	elseif isV3(b) then
		return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
	end
	fail("invalid argument to Vector3 /")
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return string.format("%g, %g, %g", v.X, v.Y, v.Z)
end
function V3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a, b, t)
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3.Max(a, b)
	return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function V3.Min(a, b)
	return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
Vector3 = {
	new = v3,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

local V2 = { __type = "Vector2" }
V2.__index = function(v, key)
	if key == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end
	fail(tostring(key) .. " is not a valid member of Vector2")
end
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
V2.__mul = function(a, b)
	if type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a * b.X, a * b.Y)
end
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
Vector2 = { new = v2, zero = v2(0, 0), one = v2(1, 1) }

--------------------------------------------------------------------------------
-- CFrame: rotation matrix (columns = right, up, back) + position

local CF = { __type = "CFrame" }
local function cf(px, py, pz, r)
	return setmetatable({ p = v3(px, py, pz), r = r or { 1, 0, 0, 0, 1, 0, 0, 0, 1 } }, CF)
end
local function isCF(v)
	return getmetatable(v) == CF
end
-- r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 } (row-major)
local function mulR(a, b)
	local out = {}
	for i = 0, 2 do
		for j = 0, 2 do
			local sum = 0
			for k = 0, 2 do
				sum += a[i * 3 + k + 1] * b[k * 3 + j + 1]
			end
			out[i * 3 + j + 1] = sum
		end
	end
	return out
end
local function rotV(r, v)
	return v3(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end
local function transpose(r)
	return { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
end
local function fromColumns(x, y, z)
	return { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z }
end
local function rotX(a)
	local c, s = math.cos(a), math.sin(a)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function rotY(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rotZ(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end
local function axisAngle(axis, angle)
	local u = axis.Unit
	local c, s, t = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
	local x, y, z = u.X, u.Y, u.Z
	return {
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c,
	}
end
local function checkNumber(...)
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if type(value) ~= "number" then
			fail("invalid argument #" .. i .. " (number expected, got " .. rtype(value) .. ")")
		end
		if value ~= value then
			fail("argument #" .. i .. " is NaN")
		end
	end
end
CF.__index = function(c, key)
	if key == "Position" then
		return c.p
	elseif key == "X" then
		return c.p.X
	elseif key == "Y" then
		return c.p.Y
	elseif key == "Z" then
		return c.p.Z
	elseif key == "RightVector" or key == "XVector" then
		return v3(c.r[1], c.r[4], c.r[7])
	elseif key == "UpVector" or key == "YVector" then
		return v3(c.r[2], c.r[5], c.r[8])
	elseif key == "LookVector" then
		return v3(-c.r[3], -c.r[6], -c.r[9])
	elseif key == "ZVector" then
		return v3(c.r[3], c.r[6], c.r[9])
	elseif key == "Rotation" then
		return cf(0, 0, 0, c.r)
	end
	local method = rawget(CF, key)
	if method then
		return method
	end
	fail(tostring(key) .. " is not a valid member of CFrame")
end
CF.__mul = function(a, b)
	if isCF(b) then
		local p = a.p + rotV(a.r, b.p)
		return cf(p.X, p.Y, p.Z, mulR(a.r, b.r))
	elseif isV3(b) then
		return a.p + rotV(a.r, b)
	end
	fail("invalid argument to CFrame * (" .. rtype(b) .. ")")
end
CF.__add = function(a, b)
	if not isV3(b) then
		fail("CFrame + expects a Vector3")
	end
	local p = a.p + b
	return cf(p.X, p.Y, p.Z, a.r)
end
CF.__sub = function(a, b)
	if not isV3(b) then
		fail("CFrame - expects a Vector3")
	end
	local p = a.p - b
	return cf(p.X, p.Y, p.Z, a.r)
end
function CF.Inverse(c)
	local rt = transpose(c.r)
	local p = -rotV(rt, c.p)
	return cf(p.X, p.Y, p.Z, rt)
end
function CF.ToObjectSpace(c, other)
	return c:Inverse() * other
end
function CF.ToWorldSpace(c, other)
	return c * other
end
function CF.VectorToWorldSpace(c, v)
	return rotV(c.r, v)
end
function CF.VectorToObjectSpace(c, v)
	return rotV(transpose(c.r), v)
end
function CF.PointToWorldSpace(c, v)
	return c * v
end
function CF.PointToObjectSpace(c, v)
	return rotV(transpose(c.r), v - c.p)
end
function CF.Lerp(a, b, t)
	local rel = mulR(transpose(a.r), b.r)
	local cosA = math.clamp((rel[1] + rel[5] + rel[9] - 1) / 2, -1, 1)
	local angle = math.acos(cosA)
	local r = a.r
	if angle > 1e-6 then
		local axis = v3(rel[8] - rel[6], rel[3] - rel[7], rel[4] - rel[2])
		if axis.Magnitude > 1e-9 then
			r = mulR(a.r, axisAngle(axis, angle * t))
		end
	end
	local p = a.p:Lerp(b.p, t)
	return cf(p.X, p.Y, p.Z, r)
end
function CF.GetComponents(c)
	local r = c.r
	return c.p.X, c.p.Y, c.p.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end
CF.__tostring = function(c)
	return "CFrame(" .. tostring(c.p) .. ")"
end
CFrame = {}
function CFrame.new(a, b, c)
	if a == nil then
		return cf(0, 0, 0)
	elseif isV3(a) then
		if b ~= nil then
			return CFrame.lookAt(a, b)
		end
		return cf(a.X, a.Y, a.Z)
	end
	checkNumber(a, b, c)
	return cf(a, b, c)
end
function CFrame.Angles(x, y, z)
	checkNumber(x, y, z)
	return cf(0, 0, 0, mulR(mulR(rotX(x), rotY(y)), rotZ(z)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromOrientation(x, y, z)
	checkNumber(x, y, z)
	return cf(0, 0, 0, mulR(mulR(rotY(y), rotX(x)), rotZ(z)))
end
CFrame.fromEulerAnglesYXZ = CFrame.fromOrientation
function CFrame.fromAxisAngle(axis, angle)
	if not isV3(axis) then
		fail("fromAxisAngle expects a Vector3")
	end
	checkNumber(angle)
	return cf(0, 0, 0, axisAngle(axis, angle))
end
function CFrame.lookAt(at, target, up)
	up = up or Vector3.yAxis
	local look = (target - at).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(Vector3.zAxis)
	end
	right = right.Unit
	local up2 = right:Cross(look)
	return cf(at.X, at.Y, at.Z, fromColumns(right, up2, -look))
end
function CFrame.fromMatrix(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy).Unit
	return cf(pos.X, pos.Y, pos.Z, fromColumns(vx, vy, vz))
end
CFrame.identity = cf(0, 0, 0)

--------------------------------------------------------------------------------
-- Color3, sequences, ranges, UDim2

local C3 = { __type = "Color3" }
C3.__index = function(c, key)
	local method = rawget(C3, key)
	if method then
		return method
	end
	fail(tostring(key) .. " is not a valid member of Color3")
end
local function c3(r, g, b)
	checkNumber(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, C3)
end
function C3.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3.ToHSV(c)
	local max, min = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
	return 0, max > 0 and (max - min) / max or 0, max
end
Color3 = {
	new = function(r, g, b)
		return c3(r or 0, g or 0, b or 0)
	end,
	fromRGB = function(r, g, b)
		return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
	end,
	fromHSV = function(h, s, v)
		return c3(v, v * (1 - s), v * (1 - s))
	end,
}

local NSK = { __type = "NumberSequenceKeypoint" }
NSK.__index = NSK
NumberSequenceKeypoint = {
	new = function(t, v, e)
		checkNumber(t, v)
		if e ~= nil then
			checkNumber(e)
		end
		return setmetatable({ Time = t, Value = v, Envelope = e or 0 }, NSK)
	end,
}
local function validateKeys(keys, what)
	if #keys < 2 then
		fail(what .. ": needs at least 2 keypoints")
	end
	if #keys > 20 then
		fail(what .. ": more than 20 keypoints")
	end
	if keys[1].Time ~= 0 then
		fail(what .. ": first keypoint must be at time 0 (got " .. keys[1].Time .. ")")
	end
	if math.abs(keys[#keys].Time - 1) > 1e-9 then
		fail(what .. ": last keypoint must be at time 1 (got " .. keys[#keys].Time .. ")")
	end
	for i = 2, #keys do
		if keys[i].Time < keys[i - 1].Time then
			fail(what .. ": keypoint times must be ascending (" .. keys[i - 1].Time .. " then " .. keys[i].Time .. ")")
		end
	end
end
local NS = { __type = "NumberSequence" }
NS.__index = NS
NumberSequence = {
	new = function(a, b)
		local keys
		if type(a) == "number" then
			keys = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }
		elseif type(a) == "table" then
			keys = a
			for _, key in keys do
				if getmetatable(key) ~= NSK then
					fail("NumberSequence.new: keypoints must be NumberSequenceKeypoints")
				end
			end
		else
			fail("NumberSequence.new: bad argument")
		end
		validateKeys(keys, "NumberSequence")
		return setmetatable({ Keypoints = keys }, NS)
	end,
}
local CSK = { __type = "ColorSequenceKeypoint" }
CSK.__index = CSK
ColorSequenceKeypoint = {
	new = function(t, c)
		checkNumber(t)
		if rtype(c) ~= "Color3" then
			fail("ColorSequenceKeypoint.new: Color3 expected, got " .. rtype(c))
		end
		return setmetatable({ Time = t, Value = c }, CSK)
	end,
}
local CS = { __type = "ColorSequence" }
CS.__index = CS
ColorSequence = {
	new = function(a, b)
		local keys
		if rtype(a) == "Color3" then
			keys = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
		elseif type(a) == "table" then
			keys = a
			for _, key in keys do
				if getmetatable(key) ~= CSK then
					fail("ColorSequence.new: keypoints must be ColorSequenceKeypoints")
				end
			end
		else
			fail("ColorSequence.new: bad argument " .. rtype(a))
		end
		validateKeys(keys, "ColorSequence")
		return setmetatable({ Keypoints = keys }, CS)
	end,
}
local NR = { __type = "NumberRange" }
NR.__index = NR
NumberRange = {
	new = function(a, b)
		checkNumber(a)
		b = b or a
		checkNumber(b)
		if a > b then
			fail("NumberRange: min (" .. a .. ") is greater than max (" .. b .. ")")
		end
		return setmetatable({ Min = a, Max = b }, NR)
	end,
}
local UD2 = { __type = "UDim2" }
UD2.__index = UD2
UDim2 = {
	fromScale = function(x, y)
		return setmetatable({ x = x, y = y }, UD2)
	end,
	new = function(a, b, c, d)
		return setmetatable({ x = a, y = c }, UD2)
	end,
}
TweenInfo = {
	new = function(time, style, direction)
		return { Time = time, EasingStyle = style, EasingDirection = direction }
	end,
}

--------------------------------------------------------------------------------
-- Enum

local ENUM_ITEMS = {
	ParticleOrientation = { "FacingCamera", "FacingCameraWorldUp", "VelocityParallel", "VelocityPerpendicular" },
	NormalId = { "Top", "Bottom", "Front", "Back", "Left", "Right" },
	ParticleEmitterShape = { "Box", "Sphere", "Cylinder", "Disc" },
	ParticleEmitterShapeStyle = { "Volume", "Surface" },
	ParticleEmitterShapeInOut = { "Outward", "Inward", "InAndOut" },
	ParticleFlipbookLayout = { "None", "Grid2x2", "Grid4x4", "Grid8x8", "Custom" },
	ParticleFlipbookMode = { "Loop", "OneShot", "PingPong", "Random" },
	TextureMode = { "Stretch", "Wrap", "Static" },
	Material = { "Plastic", "SmoothPlastic", "Neon", "Metal", "Fabric", "Slate", "Concrete", "Glass", "ForceField", "Rock", "Ice", "Basalt", "Sand", "Grass", "Wood", "Ground", "Pebble", "Cobblestone", "Brick", "Granite", "Marble", "CrackedLava", "Asphalt", "Mud", "Snow", "Sandstone", "Limestone", "Pavement", "Salt", "Glacier", "LeafyGrass" },
	PartType = { "Ball", "Block", "Cylinder", "Wedge", "CornerWedge" },
	EasingStyle = { "Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce", "Elastic", "Exponential", "Circular", "Cubic" },
	EasingDirection = { "In", "Out", "InOut" },
	SurfaceType = { "Smooth", "Studs", "Inlet", "Universal", "Glue", "Weld", "SmoothNoOutlines" },
	MeshType = { "FileMesh", "Sphere", "Brick", "Head", "Torso", "Wedge", "Cylinder" },
	BulkMoveMode = { "FireCFrameChanged", "FireAllEvents" },
	RenderFidelity = { "Automatic", "Precise", "Performance" },
	SurfaceGuiSizingMode = { "PixelsPerStud", "FixedSize" },
	PlaybackState = { "Begin", "Delayed", "Playing", "Paused", "Completed", "Cancelled" },
	CreateAssetResult = { "Success", "PermissionDenied", "UploadFailed", "Unknown" },
	AssetCreatorType = { "User", "Group" },
	RenderPriority = { "First", "Input", "Camera", "Character", "Last" },
	CameraType = { "Custom", "Scriptable", "Fixed" },
	HighlightDepthMode = { "AlwaysOnTop", "Occluded" },
}
local EnumItemMeta = { __type = "EnumItem" }
EnumItemMeta.__index = function(item, key)
	fail(tostring(key) .. " is not a valid member of EnumItem")
end
EnumItemMeta.__tostring = function(item)
	return "Enum." .. item.EnumType .. "." .. item.Name
end
Enum = setmetatable({}, {
	__index = function(_, enumName)
		local items = ENUM_ITEMS[enumName]
		if not items then
			fail(tostring(enumName) .. " is not a valid member of Enums (add it to the test runtime if real)")
		end
		local enum = {}
		for i, name in items do
			enum[name] = setmetatable({ Name = name, Value = i - 1, EnumType = enumName }, EnumItemMeta)
		end
		local enumObject = setmetatable({}, {
			__index = function(_, itemName)
				local item = enum[itemName]
				if not item then
					fail(tostring(itemName) .. " is not a valid member of Enum." .. enumName)
				end
				return item
			end,
			__type = "Enum",
		})
		rawset(Enum, enumName, enumObject)
		return enumObject
	end,
})

--------------------------------------------------------------------------------
-- Signals and the scheduler

local frameCallbacks = {} -- RenderStepped / Heartbeat connections
local sleeping = {} -- { thread, wake, start }

local function signal()
	local s = { connections = {} }
	function s:Connect(fn)
		local connection = { fn = fn, connected = true }
		function connection:Disconnect()
			connection.connected = false
		end
		table.insert(s.connections, connection)
		return connection
	end
	function s:Once(fn)
		local c
		c = s:Connect(function(...)
			c:Disconnect()
			fn(...)
		end)
		return c
	end
	function s:Fire(...)
		for _, c in table.clone(s.connections) do
			if c.connected then
				c.fn(...)
			end
		end
	end
	function s:Wait()
		return coroutine.yield()
	end
	return s
end

local renderStepped = signal()
local heartbeat = signal()

local function resume(thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		error(debug.traceback(thread, tostring(err)), 0)
	end
end

task = {}
function task.spawn(fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(thread, ...)
	return thread
end
function task.defer(fn, ...)
	local thread = coroutine.create(fn)
	table.insert(sleeping, { thread = thread, wake = NOW, start = NOW, args = table.pack(...) })
	return thread
end
function task.delay(t, fn, ...)
	local thread = coroutine.create(fn)
	table.insert(sleeping, { thread = thread, wake = NOW + (t or 0), start = NOW, args = table.pack(...) })
	return thread
end
function task.wait(t)
	local thread = coroutine.running()
	table.insert(sleeping, { thread = thread, wake = NOW + math.max(t or 0, FRAME * 0.5), start = NOW })
	return coroutine.yield()
end
function wait(t)
	return task.wait(t)
end
function task.cancel() end

--------------------------------------------------------------------------------
-- Instances

local TYPES = {} -- class -> { prop = typeTag }
local DEFAULTS = {} -- class -> { prop = value }
local BASES = {} -- class -> base class

local function defineClass(name, base, props, defaults)
	BASES[name] = base
	TYPES[name] = props
	DEFAULTS[name] = defaults or {}
end

local function propType(class, prop)
	while class do
		local t = TYPES[class][prop]
		if t then
			return t
		end
		class = BASES[class]
	end
	return nil
end

local function defaultValue(class, prop)
	while class do
		local d = DEFAULTS[class][prop]
		if d ~= nil then
			return d
		end
		class = BASES[class]
	end
	return nil
end

local function checkType(tag, value)
	if tag == "any" then
		return true
	elseif tag == "number" then
		return type(value) == "number" and value == value
	elseif tag == "bool" then
		return type(value) == "boolean"
	elseif tag == "string" then
		return type(value) == "string"
	elseif tag == "Instance?" then
		return value == nil or rtype(value) == "Instance"
	elseif string.sub(tag, 1, 5) == "enum:" then
		return rtype(value) == "EnumItem" and value.EnumType == string.sub(tag, 6)
	end
	return rtype(value) == tag
end

defineClass("Instance", nil, { Name = "string", Archivable = "bool" })
defineClass("Folder", "Instance", {})
defineClass("Model", "Instance", { PrimaryPart = "Instance?" })
defineClass("Configuration", "Instance", {})
defineClass("ModuleScript", "Instance", {})
defineClass("BasePart", "Instance", {
	Anchored = "bool", CanCollide = "bool", CanQuery = "bool", CanTouch = "bool", CastShadow = "bool",
	Transparency = "number", Color = "Color3", Material = "enum:Material", Size = "Vector3", CFrame = "CFrame",
	Position = "Vector3", Reflectance = "number", TopSurface = "enum:SurfaceType", BottomSurface = "enum:SurfaceType",
	Locked = "bool", Massless = "bool",
}, { Anchored = false, CanCollide = true, CanQuery = true, CanTouch = true, CastShadow = true, Transparency = 0, Reflectance = 0, Locked = false, Massless = false })
defineClass("Part", "BasePart", { Shape = "enum:PartType" })
defineClass("MeshPart", "BasePart", { TextureID = "string", MeshId = "string", DoubleSided = "bool", RenderFidelity = "enum:RenderFidelity", MeshSize = "Vector3" }, { TextureID = "", DoubleSided = false })
defineClass("Attachment", "Instance", { CFrame = "CFrame", Position = "Vector3", WorldPosition = "Vector3", WorldCFrame = "CFrame", Visible = "bool" }, { Visible = false })
defineClass("ParticleEmitter", "Instance", {
	Acceleration = "Vector3", Brightness = "number", Color = "ColorSequence", Drag = "number", EmissionDirection = "enum:NormalId",
	Enabled = "bool", FlipbookFramerate = "NumberRange", FlipbookLayout = "enum:ParticleFlipbookLayout",
	FlipbookMode = "enum:ParticleFlipbookMode", FlipbookStartRandom = "bool", Lifetime = "NumberRange", LightEmission = "number",
	LightInfluence = "number", LockedToPart = "bool", Orientation = "enum:ParticleOrientation", Rate = "number", RotSpeed = "NumberRange",
	Rotation = "NumberRange", Shape = "enum:ParticleEmitterShape", ShapeInOut = "enum:ParticleEmitterShapeInOut",
	ShapePartial = "number", ShapeStyle = "enum:ParticleEmitterShapeStyle", Size = "NumberSequence", Speed = "NumberRange",
	SpreadAngle = "Vector2", Squash = "NumberSequence", Texture = "string", TimeScale = "number", Transparency = "NumberSequence",
	VelocityInheritance = "number", WindAffectsDrag = "bool", ZOffset = "number",
}, {
	Brightness = 1, Drag = 0, Enabled = true, LightEmission = 0, LightInfluence = 1, LockedToPart = false, Rate = 20,
	ShapePartial = 1, TimeScale = 1, Texture = "rbxasset://textures/particles/sparkles_main.dds", ZOffset = 0, FlipbookStartRandom = false,
	VelocityInheritance = 0, WindAffectsDrag = false,
})
defineClass("Beam", "Instance", {
	Attachment0 = "Instance?", Attachment1 = "Instance?", Brightness = "number", Color = "ColorSequence", CurveSize0 = "number",
	CurveSize1 = "number", Enabled = "bool", FaceCamera = "bool", LightEmission = "number", LightInfluence = "number",
	Segments = "number", Texture = "string", TextureLength = "number", TextureMode = "enum:TextureMode", TextureSpeed = "number",
	Transparency = "NumberSequence", Width0 = "number", Width1 = "number", ZOffset = "number",
}, { Brightness = 1, CurveSize0 = 0, CurveSize1 = 0, Enabled = true, FaceCamera = false, LightEmission = 0, LightInfluence = 0, Segments = 10, Texture = "", TextureLength = 1, TextureSpeed = 1, Width0 = 1, Width1 = 1, ZOffset = 0 })
defineClass("Trail", "Instance", {
	Attachment0 = "Instance?", Attachment1 = "Instance?", Brightness = "number", Color = "ColorSequence", Enabled = "bool",
	FaceCamera = "bool", Lifetime = "number", LightEmission = "number", LightInfluence = "number", MaxLength = "number",
	MinLength = "number", Texture = "string", TextureLength = "number", TextureMode = "enum:TextureMode", Transparency = "NumberSequence",
	WidthScale = "NumberSequence",
}, { Brightness = 1, Enabled = true, FaceCamera = false, Lifetime = 2, LightEmission = 0, LightInfluence = 0, MaxLength = 0, MinLength = 0.1, Texture = "", TextureLength = 1 })
defineClass("PointLight", "Instance", { Brightness = "number", Color = "Color3", Enabled = "bool", Range = "number", Shadows = "bool" }, { Brightness = 1, Enabled = true, Range = 8, Shadows = false })
defineClass("SpecialMesh", "Instance", { MeshType = "enum:MeshType", MeshId = "string", TextureId = "string", Scale = "Vector3", Offset = "Vector3", VertexColor = "Vector3" }, { MeshId = "", TextureId = "" })
defineClass("SurfaceGui", "Instance", {
	Face = "enum:NormalId", LightInfluence = "number", SizingMode = "enum:SurfaceGuiSizingMode", PixelsPerStud = "number",
	Brightness = "number", AlwaysOnTop = "bool", CanvasSize = "Vector2", Adornee = "Instance?",
}, { LightInfluence = 1, Brightness = 1, AlwaysOnTop = false, PixelsPerStud = 50 })
defineClass("ImageLabel", "Instance", {
	Size = "UDim2", Position = "UDim2", BackgroundTransparency = "number", Image = "string", ImageColor3 = "Color3",
	ImageTransparency = "number", ZIndex = "number",
}, { BackgroundTransparency = 0, Image = "", ImageTransparency = 0, ZIndex = 1 })
defineClass("Decal", "Instance", { Texture = "string", Color3 = "Color3", Transparency = "number", Face = "enum:NormalId", ZIndex = "number" }, { Texture = "", Transparency = 0, ZIndex = 1 })
defineClass("Highlight", "Instance", {
	FillColor = "Color3", FillTransparency = "number", OutlineColor = "Color3", OutlineTransparency = "number",
	DepthMode = "enum:HighlightDepthMode", Adornee = "Instance?", Enabled = "bool",
}, { FillTransparency = 0.5, OutlineTransparency = 0, Enabled = true })

local CLASS_DEFAULT_VALUES = {
	BasePart = function()
		return { Color = Color3.fromRGB(163, 162, 165), Material = Enum.Material.Plastic, Size = v3(4, 1, 2), CFrame = CFrame.identity, TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth }
	end,
	Part = function()
		return { Shape = Enum.PartType.Block }
	end,
	MeshPart = function()
		return { RenderFidelity = Enum.RenderFidelity.Automatic, MeshSize = v3(1, 1, 1) }
	end,
	Attachment = function()
		return { CFrame = CFrame.identity }
	end,
	ParticleEmitter = function()
		return {
			Acceleration = Vector3.zero, Color = ColorSequence.new(Color3.new(1, 1, 1)), EmissionDirection = Enum.NormalId.Top,
			FlipbookFramerate = NumberRange.new(1), FlipbookLayout = Enum.ParticleFlipbookLayout.None,
			FlipbookMode = Enum.ParticleFlipbookMode.Loop, Lifetime = NumberRange.new(5, 10),
			Orientation = Enum.ParticleOrientation.FacingCamera, RotSpeed = NumberRange.new(0), Rotation = NumberRange.new(0),
			Shape = Enum.ParticleEmitterShape.Box, ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Size = NumberSequence.new(1), Speed = NumberRange.new(5),
			SpreadAngle = Vector2.zero, Squash = NumberSequence.new(0), Transparency = NumberSequence.new(0),
		}
	end,
	Beam = function()
		return { Color = ColorSequence.new(Color3.new(1, 1, 1)), TextureMode = Enum.TextureMode.Stretch, Transparency = NumberSequence.new(0.5) }
	end,
	Trail = function()
		return { Color = ColorSequence.new(Color3.new(1, 1, 1)), TextureMode = Enum.TextureMode.Stretch, Transparency = NumberSequence.new(0.5), WidthScale = NumberSequence.new(1) }
	end,
	PointLight = function()
		return { Color = Color3.new(1, 1, 1) }
	end,
	SpecialMesh = function()
		return { MeshType = Enum.MeshType.Head, Scale = v3(1, 1, 1), Offset = Vector3.zero, VertexColor = v3(1, 1, 1) }
	end,
	SurfaceGui = function()
		return { Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize, CanvasSize = v2(800, 600) }
	end,
	ImageLabel = function()
		return { Size = UDim2.fromScale(0, 0), Position = UDim2.fromScale(0, 0), ImageColor3 = Color3.new(1, 1, 1) }
	end,
	Decal = function()
		return { Color3 = Color3.new(1, 1, 1), Face = Enum.NormalId.Front }
	end,
	Highlight = function()
		return { FillColor = Color3.new(1, 0, 0), OutlineColor = Color3.new(1, 1, 1), DepthMode = Enum.HighlightDepthMode.AlwaysOnTop }
	end,
}

local RECORD = { emits = {}, created = 0, lightsMaxRange = 0, rateEmitters = {} }

local InstanceMeta = { __type = "Instance" }
local methods = {}

local function isA(class, name)
	while class do
		if class == name then
			return true
		end
		class = BASES[class]
	end
	return false
end

local function newInstance(class)
	if not TYPES[class] then
		fail("Unable to create an Instance of type \"" .. tostring(class) .. "\" (add it to the test runtime if real)")
	end
	local obj = setmetatable({ _class = class, _props = {}, _children = {}, _parent = nil, _attributes = {}, _destroyed = false }, InstanceMeta)
	local c = class
	while c do
		if CLASS_DEFAULT_VALUES[c] then
			for k, v in CLASS_DEFAULT_VALUES[c]() do
				if obj._props[k] == nil then
					obj._props[k] = v
				end
			end
		end
		c = BASES[c]
	end
	obj._props.Name = if class == "SpecialMesh" then "Mesh" else class
	RECORD.created += 1
	return obj
end

local function parentCFrame(obj)
	local parent = obj._parent
	if parent and isA(parent._class, "BasePart") then
		return parent._props.CFrame
	elseif parent and parent._class == "Attachment" then
		return methods.worldCFrame(parent)
	end
	return CFrame.identity
end
function methods.worldCFrame(att)
	return parentCFrame(att) * att._props.CFrame
end

InstanceMeta.__index = function(obj, key)
	if type(key) == "string" and string.sub(key, 1, 1) == "_" then
		return nil -- internal fields that are unset
	end
	local method = methods[key]
	if method and type(method) == "function" and key ~= "worldCFrame" then
		return method
	end
	if key == "Parent" then
		return obj._parent
	elseif key == "ClassName" then
		return obj._class
	end
	if obj._class == "Attachment" then
		if key == "WorldPosition" then
			return methods.worldCFrame(obj).Position
		elseif key == "WorldCFrame" then
			return methods.worldCFrame(obj)
		elseif key == "Position" then
			return obj._props.CFrame.Position
		end
	end
	if isA(obj._class, "BasePart") and key == "Position" then
		return obj._props.CFrame.Position
	end
	if propType(obj._class, key) then
		local value = obj._props[key]
		if value == nil then
			value = defaultValue(obj._class, key)
		end
		return value
	end
	for _, child in obj._children do
		if child._props.Name == key then
			return child
		end
	end
	fail(tostring(key) .. " is not a valid member of " .. obj._class .. " \"" .. tostring(obj._props.Name) .. "\"")
end

InstanceMeta.__newindex = function(obj, key, value)
	if type(key) == "string" and string.sub(key, 1, 1) == "_" then
		rawset(obj, key, value)
		return
	end
	if obj._destroyed and key == "Parent" then
		fail("The Parent property of " .. obj._props.Name .. " is locked, current parent: NULL")
	end
	if key == "Parent" then
		if value ~= nil and rtype(value) ~= "Instance" then
			fail("Parent must be an Instance")
		end
		if obj._parent then
			local siblings = obj._parent._children
			for i, child in siblings do
				if child == obj then
					table.remove(siblings, i)
					break
				end
			end
		end
		obj._parent = value
		if value then
			table.insert(value._children, obj)
		end
		return
	end
	local tag = propType(obj._class, key)
	if not tag then
		fail(tostring(key) .. " is not a valid member of " .. obj._class)
	end
	if not checkType(tag, value) then
		fail("Unable to assign property " .. key .. ". " .. tag .. " expected, got " .. rtype(value)
			.. (rtype(value) == "EnumItem" and (" " .. tostring(value)) or ""))
	end
	if obj._class == "Attachment" then
		if key == "WorldPosition" then
			local rot = obj._props.CFrame.Rotation
			obj._props.CFrame = CFrame.new(parentCFrame(obj):PointToObjectSpace(value)) * rot
			return
		elseif key == "WorldCFrame" then
			obj._props.CFrame = parentCFrame(obj):ToObjectSpace(value)
			return
		elseif key == "Position" then
			obj._props.CFrame = CFrame.new(value) * obj._props.CFrame.Rotation
			return
		end
	end
	if isA(obj._class, "BasePart") and key == "Position" then
		obj._props.CFrame = CFrame.new(value) * obj._props.CFrame.Rotation
		return
	end
	if obj._class == "PointLight" and key == "Range" then
		RECORD.lightsMaxRange = math.max(RECORD.lightsMaxRange, value)
	end
	if obj._class == "ParticleEmitter" and key == "Rate" and value > 0 then
		RECORD.rateEmitters[obj] = true
	end
	obj._props[key] = value
end

InstanceMeta.__tostring = function(obj)
	return obj._props.Name
end

function methods.IsA(obj, name)
	return isA(obj._class, name)
end
function methods.GetChildren(obj)
	return table.clone(obj._children)
end
function methods.GetDescendants(obj)
	local out = {}
	local function walk(o)
		for _, child in o._children do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(obj)
	return out
end
function methods.FindFirstChild(obj, name, recursive)
	for _, child in obj._children do
		if child._props.Name == name then
			return child
		end
	end
	if recursive then
		for _, child in obj._children do
			local found = child:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function methods.WaitForChild(obj, name)
	local found = obj:FindFirstChild(name)
	if not found then
		fail("WaitForChild would yield forever: " .. obj._props.Name .. "." .. tostring(name))
	end
	return found
end
function methods.FindFirstChildOfClass(obj, class)
	for _, child in obj._children do
		if child._class == class then
			return child
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(obj, class, recursive)
	for _, child in obj._children do
		if isA(child._class, class) then
			return child
		end
		if recursive then
			local found = child:FindFirstChildWhichIsA(class, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function methods.IsDescendantOf(obj, ancestor)
	local p = obj._parent
	while p do
		if p == ancestor then
			return true
		end
		p = p._parent
	end
	return false
end
function methods.FindFirstAncestorOfClass(obj, class)
	local p = obj._parent
	while p do
		if p._class == class then
			return p
		end
		p = p._parent
	end
	return nil
end
function methods.Destroy(obj)
	for _, child in table.clone(obj._children) do
		child:Destroy()
	end
	obj.Parent = nil
	obj._destroyed = true
end
function methods.ClearAllChildren(obj)
	for _, child in table.clone(obj._children) do
		child:Destroy()
	end
end
function methods.Clone(obj)
	local copy = newInstance(obj._class)
	for k, v in obj._props do
		copy._props[k] = v
	end
	for k, v in obj._attributes do
		copy._attributes[k] = v
	end
	for _, child in obj._children do
		child:Clone().Parent = copy
	end
	if obj._class == "ParticleEmitter" and (copy._props.Rate or 0) > 0 then
		RECORD.rateEmitters[copy] = true
	end
	return copy
end
function methods.SetAttribute(obj, key, value)
	obj._attributes[key] = value
end
function methods.GetAttribute(obj, key)
	return obj._attributes[key]
end
function methods.Emit(obj, count)
	if obj._class ~= "ParticleEmitter" then
		fail("Emit is not a valid member of " .. obj._class)
	end
	checkNumber(count)
	local parent = obj._parent
	if not parent or not (parent._class == "Attachment" or isA(parent._class, "BasePart")) then
		RECORD.warn("ParticleEmitter '" .. obj._props.Name .. "' emitted with no Attachment/BasePart parent: nothing shows")
	end
	table.insert(RECORD.emits, { time = NOW, emitter = obj, count = math.floor(count), life = obj._props.Lifetime.Max })
end
function methods.Clear(obj) end
function methods.GetPropertyChangedSignal()
	return signal()
end

Instance = {
	new = function(class, parent)
		local obj = newInstance(class)
		if parent then
			obj.Parent = parent
		end
		return obj
	end,
}

--------------------------------------------------------------------------------
-- Random

local RandomMeta = { __type = "Random" }
RandomMeta.__index = RandomMeta
local seedCounter = 1
Random = {
	new = function(seed)
		seedCounter += 1
		local state = seed or seedCounter * 7919
		local self = setmetatable({ state = state }, RandomMeta)
		return self
	end,
}
function RandomMeta:_next()
	self.state = (self.state * 1103515245 + 12345) % 2147483648
	return self.state / 2147483648
end
function RandomMeta:NextNumber(a, b)
	a = a or 0
	b = b or 1
	return a + (b - a) * self:_next()
end
function RandomMeta:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end
function RandomMeta:NextUnitVector()
	local v = v3(self:_next() - 0.5, self:_next() - 0.5, self:_next() - 0.5)
	if v.Magnitude < 1e-6 then
		return Vector3.yAxis
	end
	return v.Unit
end

--------------------------------------------------------------------------------
-- Services, workspace, game

local function service(name)
	local s = newInstance("Folder")
	s._props.Name = name
	return s
end
workspace = service("Workspace")
local ground = newInstance("Part")
ground._props.Name = "Ground"
ground._props.Anchored = true
ground._props.Material = Enum.Material.Slate
ground._props.Color = Color3.fromRGB(90, 85, 80)
ground._props.Size = v3(512, 1, 512)
ground._props.CFrame = CFrame.new(0, -0.5, 0)
ground.Parent = workspace
function methods.Raycast(obj, origin, direction, params)
	if obj ~= workspace then
		fail("Raycast is not a valid member of " .. obj._class)
	end
	if not isV3(origin) or not isV3(direction) then
		fail("Raycast: Vector3 arguments expected")
	end
	if origin.Y >= 0 and origin.Y + direction.Y <= 0 then
		local t = origin.Y / -direction.Y
		local hit = origin + direction * t
		return { Position = v3(hit.X, 0, hit.Z), Instance = ground, Normal = Vector3.yAxis, Material = ground._props.Material, Distance = t * direction.Magnitude }
	end
	return nil
end
function methods.BulkMoveTo(obj, parts, cframes, mode)
	for i, part in parts do
		if not isCF(cframes[i]) then
			fail("BulkMoveTo: CFrame expected")
		end
		part._props.CFrame = cframes[i]
		RECORD.moved[part] = NOW
	end
end
RECORD.moved = {}

RaycastParams = {
	new = function()
		return { FilterDescendantsInstances = {}, RespectCanCollide = false, FilterType = nil }
	end,
}

local services = {
	Workspace = workspace,
	ReplicatedStorage = service("ReplicatedStorage"),
	RunService = {
		RenderStepped = renderStepped,
		Heartbeat = heartbeat,
		PreSimulation = heartbeat,
		IsClient = function()
			return true
		end,
		IsStudio = function()
			return true
		end,
		IsServer = function()
			return false
		end,
	},
	ContentProvider = {
		PreloadAsync = function() end,
	},
	TweenService = {},
	Players = { LocalPlayer = nil },
	Debris = {
		AddItem = function(_, item, t)
			task.delay(t, function()
				item:Destroy()
			end)
		end,
	},
}

local tweens = {}
function services.TweenService.Create(_, instance, info, props)
	for key, value in props do
		local tag = propType(instance._class, key)
		if not tag then
			fail("TweenService:Create no property named '" .. key .. "' on " .. instance._class)
		end
		if not checkType(tag, value) then
			fail("TweenService:Create property " .. key .. " expects " .. tag .. ", got " .. rtype(value))
		end
		if tag ~= "number" and tag ~= "Vector3" and tag ~= "Color3" and tag ~= "CFrame" then
			fail("TweenService:Create can't tween " .. key .. " (" .. tag .. ")")
		end
	end
	local tween = { PlaybackState = Enum.PlaybackState.Begin, Completed = signal() }
	local from = {}
	function tween:Play()
		for key in props do
			from[key] = instance[key]
		end
		tween.start = NOW
		tween.PlaybackState = Enum.PlaybackState.Playing
		table.insert(tweens, tween)
	end
	function tween:Pause()
		tween.PlaybackState = Enum.PlaybackState.Paused
	end
	function tween:Cancel()
		tween.PlaybackState = Enum.PlaybackState.Cancelled
	end
	function tween:_step()
		if tween.PlaybackState ~= Enum.PlaybackState.Playing then
			return true
		end
		if instance._destroyed then
			return true
		end
		local alpha = if info.Time <= 0 then 1 else math.clamp((NOW - tween.start) / info.Time, 0, 1)
		for key, target in props do
			local a = from[key]
			local value
			if type(target) == "number" then
				value = a + (target - a) * alpha
			elseif isCF(target) then
				value = a:Lerp(target, alpha)
			else
				value = a:Lerp(target, alpha)
			end
			instance[key] = value
		end
		if alpha >= 1 then
			tween.PlaybackState = Enum.PlaybackState.Completed
			tween.Completed:Fire(Enum.PlaybackState.Completed)
			return true
		end
		return false
	end
	return tween
end

game = setmetatable({}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_, name)
				local s = services[name]
				if not s then
					fail("GetService: unknown service " .. tostring(name) .. " (add it to the test runtime if real)")
				end
				return s
			end
		elseif key == "Workspace" then
			return workspace
		end
		local s = services[key]
		if s then
			return s
		end
		fail(tostring(key) .. " is not a valid member of DataModel")
	end,
})

--------------------------------------------------------------------------------
-- Modules and require

local moduleCache = {}
local realRequire = require
function require(module)
	if rtype(module) ~= "Instance" or module._class ~= "ModuleScript" then
		fail("require expects a ModuleScript, got " .. rtype(module))
	end
	if moduleCache[module] == nil then
		local result = module._source(module)
		if result == nil then
			fail("module " .. module._props.Name .. " returned nothing")
		end
		moduleCache[module] = result
	end
	return moduleCache[module]
end

local Runtime = {}
Runtime.RECORD = RECORD
Runtime.services = services

-- Adds a ModuleScript at a dotted path under ReplicatedStorage (folders are created).
function Runtime.addModule(path, source)
	local node = services.ReplicatedStorage
	local parts = string.split(path, ".")
	for i = 1, #parts - 1 do
		local child = node:FindFirstChild(parts[i])
		if not child then
			child = newInstance("Folder")
			child._props.Name = parts[i]
			child.Parent = node
		end
		node = child
	end
	local module = newInstance("ModuleScript")
	module._props.Name = parts[#parts]
	module._source = source
	module.Parent = node
	return module
end

function Runtime.now()
	return NOW
end

-- Advances the virtual clock one frame: RenderStepped/Heartbeat, tweens, sleeping threads.
function Runtime.step()
	NOW += FRAME
	renderStepped:Fire(FRAME)
	heartbeat:Fire(FRAME)
	for i = #tweens, 1, -1 do
		if tweens[i]:_step() then
			table.remove(tweens, i)
		end
	end
	local ready = {}
	for i = #sleeping, 1, -1 do
		if sleeping[i].wake <= NOW + 1e-9 then
			table.insert(ready, sleeping[i])
			table.remove(sleeping, i)
		end
	end
	table.sort(ready, function(a, b)
		return a.wake < b.wake
	end)
	for _, entry in ready do
		if entry.args then
			resume(entry.thread, table.unpack(entry.args, 1, entry.args.n))
		else
			resume(entry.thread, NOW - entry.start)
		end
	end
	-- continuous emitters (Rate > 0)
	for emitter in RECORD.rateEmitters do
		local props = emitter._props
		if not emitter._destroyed and emitter._parent and (props.Enabled ~= false) and (props.Rate or 0) > 0 then
			emitter._owed = (emitter._owed or 0) + props.Rate * FRAME
			local n = math.floor(emitter._owed)
			if n > 0 then
				emitter._owed -= n
				table.insert(RECORD.emits, { time = NOW, emitter = emitter, count = n, life = props.Lifetime.Max, rate = true })
			end
		end
	end
end

function Runtime.newInstance(class)
	return newInstance(class)
end

function Runtime.isMovedRecently(part, within)
	local t = RECORD.moved[part]
	return t ~= nil and NOW - t <= within
end

return Runtime
