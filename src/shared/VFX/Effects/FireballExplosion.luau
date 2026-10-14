-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/FireballExplosion
-- Stylized cartoon explosion: a spiky flash bursts into a cluster of glowing balls
-- that cool from white-hot through spotted orange into dark maroon balls with glowing
-- rims; the lower balls melt into a dark gas cloud that puffs out under the top two,
-- ringed by glowing bands, and the top balls dissolve away, leaving glowing lava
-- cracks on the ground. Layers: starburst flash, fireball balls (body, spot/lava
-- shells, rim glow, halo), shock dome, floor glow/rays/dust, sparks, fire comets with
-- smoke trails, dark gas dome with glowing bands, lava cracks, embers, ground haze and
-- smoke wisps, light.
--
-- ctx.CFrame: the explosion point. The effect sits on the ground below it;
-- LookVector (toward the viewer) only orients the layout.
--
-- Each ball is a Neon body (its colour cools over time) inside textured shells
-- (MeshPart texture alpha cuts out once Transparency > 0; MeshPart textures ignore
-- Part.Color, so their colours are baked): blotchy spots while hot, then glowing lava
-- patches on the top balls. The top balls cool ~TopDelay later; to vanish, their lava
-- shell steps through the FireMelt textures (held upright, holes eat it bottom-up) while
-- the body fades. The rim is a camera-facing soft ring particle per ball, edited live.
-- The gas dome is particles only: a dark soft disc centred on the ground (the ground
-- hides its lower half, so it reads as a dome), a lit shell rim, and flat neon rings.
-- Mesh: SmoothSphere (MeshFactory "Sphere").

local ContentProvider = game:GetService("ContentProvider")

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
-- "Custom" = made for this effect (numpy in Blender, uploaded with the Studio MCP).
local ASSETS = {
	Starburst = "rbxassetid://136210055019402", -- Custom: ~22 irregular spikes on a jagged core, white
	SpotsRed = "rbxassetid://92499735743228", -- Custom: big soft red-brown blotches (~38% cover), equirect 2:1 (SmoothSphere UVs)
	Lava = "rbxassetid://131956550786641", -- Custom: large glowing orange lava patches (~32% cover), equirect 2:1
	Melt = { -- Custom: dark maroon shell with growing holes (dark charred edges) eating it from the bottom (v = 1) up
		"rbxassetid://97192842313897",
		"rbxassetid://107466624382592",
		"rbxassetid://71343323375230",
		"rbxassetid://123175405602181",
		"rbxassetid://131955014206452",
		"rbxassetid://89698118968969",
		"rbxassetid://70595154030083",
	},
	GasDisc = "rbxassetid://13580366694", -- StaticVFXTextures/glowing ring (filled disc, bright soft rim): tinted dark = the gas dome
	GasShell = "rbxassetid://135297534254471", -- StaticVFXTextures/Sphere_Mask_02 (faint sphere shell, lit rim)
	BandArc = "rbxassetid://132232127473921", -- Custom: glowing lower half of an ellipse (front of a ring seen from ~25 deg up), square, white
	LavaCracks = "rbxassetid://89120608419510", -- Custom: few large angular cells + tendrils, elongated 1.75:1, baked yellow core / orange glow
	RadialDust = "rbxassetid://72281968873307", -- Custom: soft radial smudges around an empty centre, white
	RimRing = "rbxassetid://15058135927", -- StaticVFXTextures/thick ring 2 (soft band; outer edge ~ half-width / 1.3)
	SoftGlow = "rbxassetid://284205403", -- StaticVFXTextures/Blurred Spec 11
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	Smoke = "rbxassetid://111394301752764", -- StaticVFXTextures/smoke 41
	TrailStreaks = "rbxassetid://13280046773", -- MigratedBeams/BeamSoftBlurredStreaks
}

-- Layout frame: X = the viewer's right, Y up, +Z toward the viewer (studs at Scale 1).
-- Balls, relative to the cluster centre: { x, y, z, diameter, top }. Top balls stay;
-- the others melt into the gas dome.
local BALLS = {
	{ 2.0, 0.2, -0.2, 4.3, false },
	{ -1.9, 0.1, -0.3, 4.0, false },
	{ -1.2, 2.7, -0.5, 3.5, true },
	{ 1.0, 2.6, -0.9, 3.7, true },
	{ -0.1, 0.8, 1.4, 3.3, false },
	{ -2.9, -0.4, 1.0, 2.9, false },
}

-- Comet launch directions (normalised in Play): left ~25 deg above horizontal,
-- right ~45 deg, the top one ~20 deg left of vertical.
local COMETS = {
	Vector3.new(-0.9, 0.42, 0.15),
	Vector3.new(0.7, 0.7, 0.05),
	Vector3.new(-0.34, 0.94, 0.1),
}

local WHITE = Color3.new(1, 1, 1)

-- Preload the custom textures so the first explosion doesn't draw blank shells
-- (a new texture is blank for its first frames). Never blocks the require.
task.spawn(function()
	local list = {}
	local function add(id)
		local decal = Instance.new("Decal")
		decal.Texture = id
		table.insert(list, decal)
	end
	for _, key in { "Starburst", "SpotsRed", "Lava", "LavaCracks", "RadialDust", "BandArc" } do
		add(ASSETS[key])
	end
	for _, id in ASSETS.Melt do
		add(id)
	end
	pcall(ContentProvider.PreloadAsync, ContentProvider, list)
end)

--------------------------------------------------------------------------------
-- helpers

local meshRoot = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
local meshFolder = meshRoot and meshRoot:FindFirstChild("Meshes")

local function seq(points)
	local keypoints = {}
	for _, point in points do
		table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2], point[3] or 0))
	end
	return NumberSequence.new(keypoints)
end

local function colors(points)
	local keypoints = {}
	for _, point in points do
		table.insert(keypoints, ColorSequenceKeypoint.new(point[1], point[2]))
	end
	return ColorSequence.new(keypoints)
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightInfluence = 0
	for key, value in props do
		e[key] = value
	end
	e.Parent = parent
	return e
end

-- Value of a keyframe track { {time, value}, ... } at t (numbers or Color3),
-- smoothstepped between keys and held at both ends.
local function track(keys, t)
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b[1] then
			local alpha = (t - a[1]) / math.max(b[1] - a[1], 1e-6)
			alpha = alpha * alpha * (3 - 2 * alpha)
			if typeof(a[2]) == "Color3" then
				return a[2]:Lerp(b[2], alpha)
			end
			return a[2] + (b[2] - a[2]) * alpha
		end
	end
	return keys[#keys][2]
end

local function findGround(ctx)
	local origin = ctx.CFrame.Position
	local params = RaycastParams.new()
	params.RespectCanCollide = true
	local exclude = { ctx.Folder }
	params.FilterDescendantsInstances = exclude
	for _ = 1, 4 do
		local hit = workspace:Raycast(origin, Vector3.new(0, -30, 0), params)
		if not hit then
			break
		end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			table.insert(exclude, model)
			params.FilterDescendantsInstances = exclude
		else
			return hit.Position
		end
	end
	return origin - Vector3.new(0, 2.6, 0)
end

local function setupPart(part, material, color, transparency)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material
	part.Color = color
	part.Transparency = transparency
	return part
end

-- Clone a mesh template from Assets.Meshes, or build a plain Ball fallback.
-- Returns the part and whether it is the real mesh (can show a texture).
local function newMesh(ctx, name, material, color, transparency, textureId)
	local template = meshFolder and meshFolder:FindFirstChild(name)
	local part
	if template then
		part = template:Clone()
		if textureId then
			part.TextureID = textureId
		end
	else
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Ball
		if textureId then
			transparency = 1 -- a plain part can't show the texture: hide the shell
		end
	end
	setupPart(part, material, color, transparency)
	part.Parent = ctx.Folder
	return part, template ~= nil
end

-- Emit the whole particles accumulated in `acc`; returns the remainder
local function drain(ctx, e, acc)
	if acc >= 1 then
		local n = math.floor(acc)
		ctx.Emit(e, n)
		return acc - n
	end
	return acc
end

--------------------------------------------------------------------------------

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(255, 138, 32), -- orange: halo, comets, sparks, rims while hot
	HotColor = Color3.fromRGB(255, 250, 232), -- white-hot balls just after the flash
	CreamColor = Color3.fromRGB(255, 205, 140), -- cream balls as the spots appear
	WarmColor = Color3.fromRGB(255, 110, 25), -- warm orange spotted balls (Neon reads lighter/yellower)
	FlashColor = Color3.fromRGB(255, 95, 20), -- starburst spikes (the core is white)
	DeepColor = Color3.fromRGB(225, 65, 15), -- red-orange balls between orange and dark, flame tails
	DarkColor = Color3.fromRGB(60, 10, 7), -- dark maroon cooled balls (Neon shows it brighter; never black)
	RimColor = Color3.fromRGB(255, 70, 18), -- glowing rims once cooled
	GasColor = Color3.fromRGB(26, 6, 5), -- the dark gas dome
	BandColor = Color3.fromRGB(255, 60, 15), -- glowing bands around the gas dome
	SmokeColor = Color3.fromRGB(110, 110, 118), -- comet smoke, ground haze, wisps
	DustColor = Color3.fromRGB(35, 35, 40), -- dark radial dust blown across the floor
	DomeColor = Color3.fromRGB(120, 124, 138), -- faint smoky shock dome
	CrackTint = Color3.fromRGB(255, 255, 255), -- multiplies the cracks' baked orange
	EmberColor = Color3.fromRGB(255, 150, 70),
	Scale = 1,
	BallCount = 6, -- 1-6 balls in the cluster
	BallSize = 1, -- multiplier on the ball diameters
	FlashSize = 7.5, -- studs, half-width of the starburst
	FlashTime = 0.05, -- seconds the starburst lasts
	CoolTime = 0.42, -- seconds until the lower balls have turned dark maroon
	TopDelay = 0.1, -- seconds the top balls hold their spotted orange look before cooling
	SinkTime = 0.62, -- seconds when the lower balls have melted into the gas dome
	GasStart = 0.42, -- seconds when the gas dome starts puffing out
	GasTime = 0.78, -- seconds the gas dome lasts (it thins out over its last ~35%)
	CrumbleStart = 0.6, -- seconds when the top balls start dissolving
	CrumbleTime = 0.2, -- seconds the top balls take to dissolve
	CometCount = 3, -- 0-3 fire comets
	CometSpeed = 28, -- studs/s
	CometGravity = 15, -- studs/s^2 (a slight droop)
	CometTime = 1.6, -- seconds a comet flies before it is removed
	SparkCount = 45,
	DomeSize = 9, -- studs, final half-width of the shock dome
	BaseSize = 10, -- studs, width of the gas dome
	CrackSize = 4.3, -- studs, half-width of the lava-crack texture (the network fills ~80% of it)
	CrackStart = 0.78, -- seconds when the cracks appear
	CrackTime = 2.8, -- seconds the cracks glow
	EmberRate = 40, -- embers per second while the balls cool and crumble
	WispRate = 7, -- smoke wisps per second rising off the cracks
	LightBrightness = 1,
	LightRange = 10,
}

-- Play returns once the cracks are 75% through CrackTime (~2.9 s); then the cracks
-- (0.25 * 2.8 = 0.7 s) and the last wisps (Lifetime up to 1.4 s) still fade.
Effect.Linger = 1.5

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local ballScale = s * p.BallSize

	local ground = findGround(ctx)
	local look = ctx.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	-- facing away from the viewer, like a camera: X = viewer's right, +Z = toward viewer
	local frame = CFrame.lookAt(ground, ground - look.Unit)
	local center = frame * CFrame.new(0, 2.3 * ballScale, 0) -- cluster centre

	local anchor = ctx.Anchor(CFrame.new(ground))
	local groundAtt = Instance.new("Attachment")
	groundAtt.Position = Vector3.new(0, 0.12 * s, 0)
	groundAtt.Parent = anchor
	local centerAtt = Instance.new("Attachment")
	centerAtt.Parent = anchor
	centerAtt.WorldPosition = center.Position

	local appear = 0.03 -- balls replace the flash
	local coolT = p.CoolTime
	local sinkT = p.SinkTime
	local crumbleStart = p.CrumbleStart
	local crumbleEnd = crumbleStart + p.CrumbleTime

	-- 1. Starburst flash: orange spikes over a wide white-hot core ------------------
	local flashLife = NumberRange.new(p.FlashTime)
	local flashFade = seq({ { 0, 0 }, { 0.75, 0.05 }, { 1, 1 } })
	local spikes = emitter(centerAtt, {
		Texture = ASSETS.Starburst,
		Color = ColorSequence.new(p.FlashColor),
		LightEmission = 1,
		Brightness = 2,
		Speed = NumberRange.new(0),
		Lifetime = flashLife,
		Rotation = NumberRange.new(-8, 8),
		Size = seq({ { 0, p.FlashSize * s * 0.8 }, { 0.3, p.FlashSize * s }, { 1, p.FlashSize * s * 1.05 } }),
		Transparency = flashFade,
		ZOffset = 8, -- in front of the balls and clear of the ground
	})
	local flashCore = emitter(centerAtt, {
		Texture = ASSETS.SoftGlow,
		Color = ColorSequence.new(WHITE),
		LightEmission = 1,
		Brightness = 3,
		Speed = NumberRange.new(0),
		Lifetime = flashLife,
		Size = NumberSequence.new(p.FlashSize * s * 0.42),
		Squash = NumberSequence.new(-0.5), -- negative Squash = wider than tall
		Transparency = flashFade,
		ZOffset = 8.1,
	})
	ctx.Emit(spikes, 1)
	ctx.Emit(flashCore, 1)

	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = math.min(p.LightRange * s, 20) -- budget: Range <= 20
	light.Brightness = p.LightBrightness
	light.Parent = centerAtt

	-- 2. Balls ------------------------------------------------------------------------
	local balls = {}
	local hasSphere = meshFolder ~= nil and meshFolder:FindFirstChild("SmoothSphere") ~= nil
	for i = 1, math.clamp(math.floor(p.BallCount), 0, #BALLS) do
		local b = BALLS[i]
		local att = Instance.new("Attachment")
		att.Parent = anchor
		local rim = emitter(att, {
			Texture = ASSETS.RimRing,
			LightEmission = 1,
			Speed = NumberRange.new(0),
			Lifetime = NumberRange.new(crumbleEnd + 1),
			LockedToPart = true, -- follows the attachment as the ball moves
			Color = ColorSequence.new(p.Color),
			Size = NumberSequence.new(0),
			Transparency = NumberSequence.new(1),
			ZOffset = b[4] * ballScale * 0.5, -- draw at the ball's front surface
		})
		table.insert(balls, {
			Offset = Vector3.new(b[1], b[2], b[3]) * ballScale,
			Diameter = b[4] * ballScale,
			Top = b[5],
			Delay = if b[5] then p.TopDelay else 0,
			Spin = CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28),
			SpinRate = (math.random() - 0.5) * 0.8, -- radians/s, slow tumble of the pattern
			Body = newMesh(ctx, "SmoothSphere", Enum.Material.Neon, p.HotColor, 1),
			Spots = newMesh(ctx, "SmoothSphere", Enum.Material.Neon, WHITE, 1, ASSETS.SpotsRed),
			-- top balls: lava patches, then the dissolving shell (lower balls melt into the gas)
			Shell = if b[5] then newMesh(ctx, "SmoothSphere", Enum.Material.Neon, WHITE, 1, ASSETS.Lava) else nil,
			Att = att,
			Rim = rim,
			Stage = 0,
			IsMesh = hasSphere, -- false: plain Ball fallbacks, the textured shells stay hidden
		})
	end

	-- the cluster bursts out of a small core in ~0.03 s (balls grow and fly apart to their
	-- places), then keeps swelling slowly
	local sizeKeys = { { appear, 0.15 }, { appear + 0.02, 0.9 }, { 0.08, 1.05 }, { 0.2, 1.12 }, { 0.42, 1.18 }, { crumbleEnd, 1.25 } }
	local spreadKeys = { { appear, 0.2 }, { appear + 0.02, 0.95 }, { 0.08, 1.08 }, { 0.42, 1.15 } }
	-- per-ball tracks, in "ball time" (effect time minus the ball's Delay)
	local bodyKeys = {
		{ 0, p.HotColor },
		{ 0.12, p.HotColor },
		{ 0.2, p.CreamColor },
		{ 0.3, p.WarmColor },
		{ 0.36, p.DeepColor },
		{ coolT, p.DarkColor },
		{ coolT + 0.15, p.DarkColor:Lerp(Color3.new(), 0.15) }, -- dark maroon, nearly unlit once the lava fades
	}
	local rimColorKeys = { { 0.2, p.Color }, { coolT, p.Color:Lerp(p.RimColor, 0.5) }, { 0.7, p.RimColor } }
	local rimSizeKeys = { { 0.05, 1.45 }, { 0.3, 1.38 }, { 0.42, 1.3 } } -- x ball radius
	-- a soft warm edge while hot, the bright fresnel ring once dark, faint by ~0.73
	local rimAlphaKeys = { { appear, 1 }, { 0.06, 0.55 }, { 0.3, 0.25 }, { 0.42, 0 }, { 0.45, 0.6 }, { 0.5, 0.88 }, { 0.58, 1 } }
	-- shell transparency (1 = hidden)
	local spotsAlpha = { { 0.11, 1 }, { 0.15, 0.93 }, { 0.21, 0.8 }, { 0.3, 0.1 }, { 0.4, 0.1 }, { 0.5, 1 } }
	local lavaAlpha = { { 0.38, 1 }, { 0.43, 0.05 }, { 0.52, 0.1 }, { 0.62, 0.85 }, { 0.7, 1 } }
	local sinkKeys = { { 0.42, 0 }, { sinkT, 1 } }
	-- shell texture while dissolving: Melt[1..n] over the dissolve, k = 0..1
	local function ashTexture(k)
		return ASSETS.Melt[math.clamp(1 + math.floor(k * #ASSETS.Melt), 1, #ASSETS.Melt)]
	end

	-- diffuse orange bloom around the hot cluster
	local halo = emitter(centerAtt, {
		Texture = ASSETS.SoftGlow,
		Color = ColorSequence.new(p.Color),
		LightEmission = 1,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.4),
		Size = seq({ { 0, 5.5 * ballScale }, { 0.5, 7 * ballScale }, { 1, 7.5 * ballScale } }),
		Transparency = seq({ { 0, 0.3 }, { 0.5, 0.55 }, { 1, 1 } }),
		ZOffset = 5, -- pulled toward the camera so the ground doesn't cut it flat
	})

	-- 3. Shock dome, floor glow + rays + dust, sparks (at `appear`) -------------------
	-- shock dome: a soft grey ring (no fill), camera-facing and centred on the ground so
	-- the ground cuts it into an arc; its band sits at ~half-width / 1.3
	local dome = emitter(groundAtt, {
		Texture = ASSETS.RimRing,
		Color = ColorSequence.new(p.DomeColor),
		LightEmission = 0.2,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.2),
		Rotation = NumberRange.new(0, 360),
		Size = seq({ { 0, p.DomeSize * s * 0.75 }, { 0.5, p.DomeSize * s * 1.1 }, { 1, p.DomeSize * s * 1.25 } }),
		Transparency = seq({ { 0, 0.3 }, { 0.5, 0.5 }, { 1, 1 } }),
	})
	-- particles lying flat on the floor
	local function flatEmitter(props)
		props.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		props.EmissionDirection = Enum.NormalId.Top
		props.Speed = NumberRange.new(0.01)
		return emitter(groundAtt, props)
	end
	local groundGlow = flatEmitter({
		Texture = ASSETS.SoftGlow,
		Color = ColorSequence.new(p.Color),
		LightEmission = 1,
		Lifetime = NumberRange.new(0.25),
		Size = seq({ { 0, 4 * s }, { 0.3, 6.5 * s }, { 1, 7 * s } }),
		Transparency = seq({ { 0, 0.2 }, { 0.4, 0.45 }, { 1, 1 } }),
	})
	local floorRays = flatEmitter({
		Texture = ASSETS.Starburst,
		Color = ColorSequence.new(p.FlashColor),
		LightEmission = 1,
		Lifetime = NumberRange.new(0.13),
		Rotation = NumberRange.new(0, 360),
		Size = seq({ { 0, 4.5 * s }, { 1, 6.5 * s } }),
		Transparency = seq({ { 0, 0.1 }, { 0.5, 0.35 }, { 1, 1 } }),
	})
	local dust = flatEmitter({
		Texture = ASSETS.RadialDust,
		Color = ColorSequence.new(p.DustColor),
		LightEmission = 0,
		Lifetime = NumberRange.new(0.6),
		Rotation = NumberRange.new(0, 360),
		Size = seq({ { 0, 4.5 * s }, { 0.4, 7 * s }, { 1, 8 * s } }),
		Transparency = seq({ { 0, 0.25 }, { 0.5, 0.5 }, { 1, 1 } }),
	})
	local haze = flatEmitter({
		Texture = ASSETS.Smoke,
		Color = ColorSequence.new(p.SmokeColor:Lerp(Color3.new(), 0.45)), -- unlit: keep it dark on the floor
		LightEmission = 0,
		Lifetime = NumberRange.new(0.6),
		Rotation = NumberRange.new(0, 360),
		Size = seq({ { 0, 8 * s }, { 1, 10 * s } }), -- wider than the base, which hides its centre
		Transparency = seq({ { 0, 1 }, { 0.3, 0.8 }, { 1, 1 } }),
	})
	local sparks = emitter(centerAtt, {
		Texture = ASSETS.Speck,
		Color = colors({ { 0, WHITE:Lerp(p.Color, 0.6) }, { 0.3, p.Color }, { 1, p.DeepColor } }),
		LightEmission = 1,
		Brightness = 2,
		SpreadAngle = Vector2.new(180, 180),
		Speed = NumberRange.new(30 * s, 70 * s),
		Drag = 3,
		Acceleration = Vector3.new(0, -15 * s, 0),
		Lifetime = NumberRange.new(0.35, 0.8),
		Size = seq({ { 0, 0.2 * s }, { 1, 0.05 * s } }),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(1.2), -- positive Squash = taller: dashes along the flight
		ZOffset = 1,
	})

	-- 4. Comets: a Beam (launch point -> head) and a glow on the head ---------------
	-- A Trail's lifetime is real time (breaks slow-mo and freeze-frames), so each comet
	-- is a Beam bent into the exact flight parabola: a parabola is a cubic Bezier whose
	-- control points sit 1/3 of the flight time along the start and end velocities, and
	-- a Beam's control points are its attachments' X axes times CurveSize0/1. Its
	-- colour/transparency run grey smoke -> orange flame toward the head; the flame
	-- covers the last 0.05-0.15 s of the path, so it stretches out as the comet flies,
	-- and the beam widens toward the head (a teardrop with the head glow on top).
	local comets = {}
	local gravity = Vector3.new(0, -p.CometGravity * s, 0)
	for i = 1, math.clamp(math.floor(p.CometCount), 0, #COMETS) do
		local launchAtt = Instance.new("Attachment")
		launchAtt.Parent = anchor
		local headAtt = Instance.new("Attachment")
		headAtt.Parent = anchor
		local beam = Instance.new("Beam")
		beam.Attachment0 = launchAtt
		beam.Attachment1 = headAtt
		beam.FaceCamera = true
		beam.Segments = 30
		beam.Texture = ASSETS.TrailStreaks -- soft strands across the width: a wispy ribbon
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.LightEmission = 0.6
		beam.LightInfluence = 0
		beam.Brightness = 2
		beam.Width0 = 0.06 * s
		beam.Width1 = 0.4 * s
		beam.Enabled = false
		beam.Parent = anchor
		local glow = emitter(headAtt, {
			Texture = ASSETS.SoftGlow,
			Color = ColorSequence.new(WHITE:Lerp(p.Color, 0.6)),
			LightEmission = 1,
			Brightness = 3,
			Speed = NumberRange.new(0),
			Lifetime = NumberRange.new(p.CometTime + 0.1),
			LockedToPart = true,
			Size = NumberSequence.new(0.3 * s),
			Transparency = NumberSequence.new(1),
			ZOffset = 1,
		})
		table.insert(comets, {
			Launch = launchAtt,
			Head = headAtt,
			Beam = beam,
			Glow = glow,
			Velocity = frame:VectorToWorldSpace(COMETS[i].Unit) * p.CometSpeed * s * (0.9 + 0.2 * math.random()),
		})
	end
	local cometLaunch = 0.035
	-- attachment frame whose X axis points along `dir`
	local function axisFrame(pos, dir)
		local x = dir.Unit
		local up = if math.abs(x.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
		return CFrame.fromMatrix(pos, x, (up - x * up:Dot(x)).Unit)
	end
	local smokeColor = p.SmokeColor:Lerp(Color3.new(), 0.45) -- Brightness 2 lifts it back

	-- 5. Cracks, embers, wisps ------------------------------------------------------------
	local crackAtt = Instance.new("Attachment")
	crackAtt.Parent = anchor
	crackAtt.WorldPosition = (frame * CFrame.new(0, 0.12 * s, 1.5 * s)).Position -- slightly toward the viewer
	local crackLife = p.CrackTime
	local cracks = emitter(crackAtt, {
		Texture = ASSETS.LavaCracks,
		-- the baked yellow-orange deepens toward orange-red as the cracks cool
		Color = colors({
			{ 0, p.CrackTint },
			{ 0.35, p.CrackTint },
			{ 1, Color3.new(p.CrackTint.R, p.CrackTint.G * 0.6, p.CrackTint.B * 0.5) },
		}),
		LightEmission = 1,
		Brightness = 1.4,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01),
		Lifetime = NumberRange.new(crackLife),
		Rotation = NumberRange.new(-15, 15), -- keep the network's long axis across the view
		Size = seq({ { 0, p.CrackSize * s * 0.7 }, { 0.05, p.CrackSize * s }, { 1, p.CrackSize * s } }),
		-- bright at first, still clearly orange at ~3.0 s, gone at CrackStart + CrackTime
		Transparency = seq({ { 0, 1 }, { 0.04, 0 }, { 0.3, 0.05 }, { 0.6, 0.25 }, { 0.79, 0.4 }, { 1, 1 } }),
	})

	-- embers rise from just above the gas dome
	local box = ctx.Anchor(frame * CFrame.new(0, p.BaseSize * s * 0.32, 0.3 * s))
	box.Size = Vector3.new(p.BaseSize * s * 0.8, 0.4 * s, p.BaseSize * s * 0.6)
	local embers = emitter(box, {
		Texture = ASSETS.Speck,
		Color = colors({ { 0, WHITE:Lerp(p.EmberColor, 0.6) }, { 1, p.EmberColor } }),
		LightEmission = 1,
		Brightness = 1.2,
		Shape = Enum.ParticleEmitterShape.Box,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(55, 55),
		Speed = NumberRange.new(3 * s, 8 * s),
		Drag = 0.8,
		Acceleration = Vector3.new(0, 1 * s, 0),
		Lifetime = NumberRange.new(0.6, 1),
		Rotation = NumberRange.new(0, 360),
		Size = seq({ { 0, 0.06 * s }, { 0.8, 0.05 * s }, { 1, 0 } }),
		Transparency = seq({ { 0, 0.2 }, { 0.7, 0.4 }, { 1, 1 } }),
	})
	-- thin curly wisps: smoke puffs stretched tall (positive Squash), spread over the cracks
	local wispArea = ctx.Anchor(CFrame.new(crackAtt.WorldPosition + Vector3.new(0, 0.3 * s, 0)))
	wispArea.Size = Vector3.new(p.CrackSize * s * 1.2, 0.2, p.CrackSize * s * 0.7)
	local wisps = emitter(wispArea, {
		Shape = Enum.ParticleEmitterShape.Box,
		Texture = ASSETS.Smoke,
		Color = ColorSequence.new(p.SmokeColor:Lerp(WHITE, 0.15)),
		LightEmission = 0,
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(15, 15),
		Speed = NumberRange.new(1.2 * s, 2 * s),
		Lifetime = NumberRange.new(1, 1.4),
		Rotation = NumberRange.new(-15, 15),
		RotSpeed = NumberRange.new(-40, 40),
		Size = seq({ { 0, 0.5 * s }, { 1, 0.85 * s } }),
		Squash = NumberSequence.new(1.3), -- tall and thin
		Transparency = seq({ { 0, 1 }, { 0.2, 0.25 }, { 1, 1 } }),
	})
	-- 5b. Gas dome: the lower balls melt into a dark cloud that puffs out under the top
	-- balls. Camera-facing filled discs centred on the ground (the ground hides their lower
	-- half, so they read as a dome), a lit rim, and glowing band arcs across its front
	-- (the front half of a ring around the dome; a full flat ring can't hide its back half
	-- behind a particle).
	local gasR = p.BaseSize * s * 0.5 -- final dome radius
	local gasLife = NumberRange.new(p.GasTime)
	local gasGrow = { { 0, 0.3 }, { 0.08, 0.9 }, { 0.3, 1 }, { 1, 1.06 } } -- puffs out in ~0.06 s, then drifts
	local function gasSize(scale)
		local keys = {}
		for _, k in gasGrow do
			table.insert(keys, { k[1], gasR * scale * k[2] })
		end
		return seq(keys)
	end
	local gasAtt = Instance.new("Attachment")
	gasAtt.Parent = anchor
	-- centred a little above the ground: the ground hides less than half, so it bulges up
	-- around the bottoms of the top balls
	gasAtt.WorldPosition = (frame * CFrame.new(0, 0.3 * gasR, -0.3 * s)).Position
	local gas = emitter(gasAtt, {
		Texture = ASSETS.GasDisc,
		Color = ColorSequence.new(p.GasColor),
		LightEmission = 0,
		Speed = NumberRange.new(0),
		Lifetime = gasLife,
		Size = gasSize(1.05), -- the disc's solid part is ~70% of its half-width
		Squash = NumberSequence.new(-0.35), -- flattened: wider than tall
		Transparency = seq({ { 0, 1 }, { 0.06, 0 }, { 0.62, 0 }, { 1, 1 } }),
	})
	local gasRim = emitter(gasAtt, {
		Texture = ASSETS.GasShell,
		Color = ColorSequence.new(p.BandColor),
		LightEmission = 1,
		Speed = NumberRange.new(0),
		Lifetime = gasLife,
		Size = gasSize(1.02),
		Squash = NumberSequence.new(-0.35),
		Transparency = seq({ { 0, 1 }, { 0.08, 0.55 }, { 0.6, 0.7 }, { 1, 1 } }),
		ZOffset = 0.5,
	})
	-- band arcs, drawn in front of the gas: { height / radius, arc size / radius, alpha }
	local bandAtts = {}
	for _, band in { { 0.5, 1.0, 0 }, { 0.15, 1.08, 0.35 } } do
		local att = Instance.new("Attachment")
		att.Parent = anchor
		att.WorldPosition = (frame * CFrame.new(0, gasR * band[1], 0)).Position
		table.insert(bandAtts, emitter(att, {
			Texture = ASSETS.BandArc,
			Color = ColorSequence.new(p.BandColor),
			LightEmission = 1,
			Brightness = 1.6,
			Speed = NumberRange.new(0),
			Lifetime = gasLife,
			Size = gasSize(band[2]),
			-- gone by ~0.95 s, before the dome thins out
			Transparency = seq({ { 0, 1 }, { 0.08, band[3] }, { 0.5, math.min(1, band[3] + 0.1) }, { 0.68, 1 }, { 1, 1 } }),
			ZOffset = gasR, -- in front of the dome's surface
		}))
	end

	-- 6. Timeline ------------------------------------------------------------------------
	local fired = {}
	local function once(name, at, t)
		if not fired[name] and t >= at then
			fired[name] = true
			return true
		end
		return false
	end
	local crackStart = p.CrackStart
	local emberAcc, wispAcc = 0, 0
	local endT = math.max(crumbleEnd, p.GasStart + p.GasTime, cometLaunch + p.CometTime, crackStart + crackLife * 0.75)
	local t = 0
	while t < endT do
		if once("burst", appear, t) then
			ctx.Emit(halo, 1)
			ctx.Emit(dome, 1)
			ctx.Emit(groundGlow, 1)
			ctx.Emit(floorRays, 1)
			ctx.Emit(dust, 1)
			ctx.Emit(sparks, p.SparkCount)
			for _, ball in balls do
				ctx.Emit(ball.Rim, 1)
			end
		end
		if once("comets", cometLaunch, t) then
			for _, comet in comets do
				ctx.Emit(comet.Glow, 1)
			end
		end
		if once("haze", 0.65, t) or once("haze2", 0.9, t) then
			ctx.Emit(haze, 3)
		end
		if once("cracks", crackStart, t) then
			ctx.Emit(cracks, 1)
		end
		if once("gas", p.GasStart, t) then
			ctx.Emit(gas, 3) -- stacked discs make the cloud opaque
			ctx.Emit(gasRim, 1)
			for _, band in bandAtts do
				ctx.Emit(band, 1)
			end
		end

		-- balls
		local size = track(sizeKeys, t)
		local spread = track(spreadKeys, t)
		local sink = track(sinkKeys, t)
		for _, ball in balls do
			-- ball time: every ball heats and spots alike; top balls then hold the spotted
			-- orange-red look for Delay seconds before cooling
			local bt = if t <= 0.34 then t else math.max(0.34, t - ball.Delay)
			local d = ball.Diameter * size
			local offset = ball.Offset * spread
			local cStart, cTime = crumbleStart, p.CrumbleTime
			local melted = false
			if ball.Top then
				offset -= Vector3.new(0, 0.6 * ballScale * sink, 0) -- settle onto the gas dome
			else
				-- lower balls shrink and sink into the gas, then vanish inside it
				d *= 1 - 0.6 * sink
				offset -= Vector3.new(0, 1.2 * ballScale * sink, 0)
				melted = t >= p.GasStart + 0.05 -- swallowed once the gas puff is opaque
			end
			local k = if ball.Top then (t - cStart) / cTime else -1 -- dissolve progress
			local crumbling = k >= 0
			local gone = k >= 1 or melted
			local cf = center * CFrame.new(offset)
			local spinCf = cf * ball.Spin * CFrame.Angles(0, ball.SpinRate * t, 0)
			local uprightCf = cf * CFrame.Angles(0, ball.SpinRate * t, 0)
			local sizeV = Vector3.one * d
			ball.Body.Size = sizeV * 0.985
			ball.Body.CFrame = cf
			ball.Body.Color = track(bodyKeys, bt)
			-- dissolving: the solid core goes quickly so the shell's holes show through
			ball.Body.Transparency = if t < appear or gone then 1 elseif crumbling then math.min(1, 0.3 + 2.5 * k) else 0
			ball.Spots.Size = sizeV
			ball.Spots.CFrame = spinCf
			ball.Spots.Transparency = if crumbling or gone or not ball.IsMesh then 1 else track(spotsAlpha, bt)
			if not ball.Shell then
				-- lower balls have no outer shell
			elseif not ball.IsMesh then
				ball.Shell.Transparency = 1
			elseif crumbling then
				ball.Shell.Size = sizeV * 1.004
				-- the shell dissolves: held upright so its holes eat the ball bottom-up
				ball.Shell.CFrame = uprightCf
				local tex = ashTexture(k)
				if ball.Stage ~= tex then
					ball.Stage = tex
					ball.Shell.TextureID = tex
				end
				ball.Shell.Transparency = if gone then 1 else 0.02 + 0.4 * k
			else
				ball.Shell.Size = sizeV * 1.004
				ball.Shell.CFrame = spinCf
				ball.Shell.Transparency = track(lavaAlpha, bt)
			end
			ball.Att.WorldPosition = cf.Position
			ball.Rim.Color = ColorSequence.new(track(rimColorKeys, bt))
			ball.Rim.Size = NumberSequence.new(d * 0.5 * track(rimSizeKeys, bt))
			-- melting balls lose their rim first (it is drawn in front, over the gas)
			local rimAlpha = track(rimAlphaKeys, bt)
			local sinkFade = if ball.Top then 0 else math.clamp(sink * 1.6, 0, 1)
			ball.Rim.Transparency = NumberSequence.new(if crumbling or gone then 1 else rimAlpha + (1 - rimAlpha) * sinkFade)
		end

		-- comets
		local age = t - cometLaunch
		for _, comet in comets do
			if age > p.CometTime then
				comet.Beam.Enabled = false
				comet.Glow.Transparency = NumberSequence.new(1)
			elseif age > 0.005 then
				local v0 = comet.Velocity
				if v0.Magnitude < 1e-3 then
					v0 = Vector3.new(0, 1e-3, 0) -- CometSpeed 0: avoid a NaN direction
				end
				local start = center.Position + v0.Unit * 1.5 * ballScale
				local headPos = start + v0 * age + gravity * (0.5 * age * age)
				local headVel = v0 + gravity * age
				comet.Launch.WorldCFrame = axisFrame(start, v0)
				comet.Head.WorldCFrame = axisFrame(headPos, headVel)
				comet.Beam.CurveSize0 = v0.Magnitude * age / 3
				comet.Beam.CurveSize1 = -headVel.Magnitude * age / 3
				-- flame = the last 0.05-0.15 s of path (as a fraction of the beam), smoke before it
				local flame = math.clamp(math.min(0.05 + age * 0.3, 0.15) / age, 0.03, 0.95)
				local f0 = 1 - flame
				local fade = track({ { 0.3, 0 }, { 0.9, 1 } }, age) -- the smoke thins out
				local flameFade = track({ { 0.8, 0 }, { p.CometTime, 1 } }, age)
				comet.Beam.Transparency = seq({
					{ 0, math.min(1, 0.8 + fade) },
					{ f0 * 0.7, math.min(1, 0.45 + fade * 0.6) },
					{ f0, math.min(1, 0.35 + fade * 0.6) },
					{ f0 + flame * 0.5, 0.2 + 0.8 * flameFade },
					{ f0 + flame * 0.85, 0.1 + 0.9 * flameFade }, -- keys are fractions of flame: always in order
					{ 1, 1 }, -- the flat beam end hides under the head glow
				})
				comet.Beam.Color = colors({
					{ 0, smokeColor },
					{ math.max(f0 - 0.001, 0.001), smokeColor },
					{ math.min(f0 + flame * 0.35, 0.997), p.DeepColor },
					{ math.min(f0 + flame * 0.8, 0.998), p.Color },
					{ 1, WHITE:Lerp(p.Color, 0.3) },
				})
				comet.Beam.Enabled = true
				comet.Glow.Transparency = NumberSequence.new(0.1 + 0.9 * flameFade)
			end
		end

		-- light: a short warm pop, then a faint red glow from the base
		light.Brightness = p.LightBrightness * track({ { 0, 1.5 }, { 0.1, 1 }, { 0.3, 0.3 }, { coolT, 0.25 }, { 1.1, 0 } }, t)
		light.Color = if t < coolT then p.Color else p.RimColor

		-- one rendered frame (also in slow-mo, so the ~20 ms burst updates every frame there)
		local dt = ctx.Wait(1 / 240)
		t += dt

		-- embers while the balls cool and crumble (thinning out by ~1.8 s), wisps off the cracks
		if t >= 0.3 and t < 1.8 then
			emberAcc += p.EmberRate * dt * (if t < 0.7 then 0.3 elseif t > 1.4 then 0.5 else 1)
		end
		if t >= 1.4 then
			wispAcc += p.WispRate * dt
		end
		emberAcc = drain(ctx, embers, emberAcc)
		wispAcc = drain(ctx, wisps, wispAcc)
	end
end

return Effect
