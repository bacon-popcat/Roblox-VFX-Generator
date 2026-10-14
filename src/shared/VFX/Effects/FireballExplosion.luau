-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/FireballExplosion
-- Stylized cartoon explosion: a spiky flash bursts into a cluster of glowing balls
-- that cool from white-hot through spotted orange into dark maroon balls with glowing
-- rims; the lower balls squash into a lumpy dark pile with a glowing band, and
-- everything crumbles to ash, leaving glowing lava cracks on the ground. Layers:
-- starburst flash, fireball balls (body, spot/lava/band shells, rim glow, halo), shock
-- dome, floor glow/rays/dust, sparks, fire comets with smoke trails, lava cracks, ash
-- flakes and chips, embers, ground haze and smoke wisps, light.
--
-- ctx.CFrame: the explosion point. The effect sits on the ground below it;
-- LookVector (toward the viewer) only orients the layout.
--
-- Each ball is a Neon body (its colour cools over time) inside textured shells
-- (MeshPart texture alpha cuts out once Transparency > 0; MeshPart textures ignore
-- Part.Color, so their colours are baked): blotchy spots while hot, then glowing lava
-- patches (top balls) or a glowing band (lower balls, squashed into the base pile, so
-- the bands line up into one stripe). To crumble, a ball's shell steps through the Ash
-- textures (held upright, holes eat it from the bottom up) while its body fades and it
-- sheds ash flakes. The top balls cool ~TopDelay later and crumble last. The rim is a
-- camera-facing soft ring particle per ball, edited live every frame.
-- Meshes: SmoothSphere (MeshFactory "Sphere"), ShellShard1/2 (Blender,
-- assets/meshes/ShellShard.fbx).

local ContentProvider = game:GetService("ContentProvider")

local VFX = script.Parent.Parent
local MeshParticles = require(VFX:WaitForChild("MeshParticles"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
-- "Custom" = made for this effect (numpy in Blender, uploaded with the Studio MCP).
local ASSETS = {
	Starburst = "rbxassetid://136210055019402", -- Custom: ~22 irregular spikes on a jagged core, white
	SpotsRed = "rbxassetid://92499735743228", -- Custom: big soft red-brown blotches (~38% cover), equirect 2:1 (SmoothSphere UVs)
	Lava = "rbxassetid://131956550786641", -- Custom: large glowing orange lava patches (~32% cover), equirect 2:1
	Ash = { -- Custom: dark maroon shell with growing holes (charred, grey-ash edges) eating it from the bottom (v = 1) up
		"rbxassetid://128007792525042",
		"rbxassetid://122706754957213",
		"rbxassetid://109708028738049",
		"rbxassetid://97494743621675",
		"rbxassetid://80840226643347",
		"rbxassetid://132990866216076",
		"rbxassetid://108174695325105",
	},
	BallBand = "rbxassetid://106509801411038", -- Custom: dark maroon with a thick glowing band above the equator (v ~0.37) + a thin one (v ~0.47), equirect 2:1
	LavaCracks = "rbxassetid://89120608419510", -- Custom: few large angular cells + tendrils, elongated 1.75:1, baked yellow core / orange glow
	RadialDust = "rbxassetid://72281968873307", -- Custom: soft radial smudges around an empty centre, white
	RimRing = "rbxassetid://15058135927", -- StaticVFXTextures/thick ring 2 (soft band; outer edge ~ half-width / 1.3)
	SoftGlow = "rbxassetid://284205403", -- StaticVFXTextures/Blurred Spec 11
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	Smoke = "rbxassetid://111394301752764", -- StaticVFXTextures/smoke 41
	TrailStreaks = "rbxassetid://13280046773", -- MigratedBeams/BeamSoftBlurredStreaks
}

-- Layout frame: X = the viewer's right, Y up, +Z toward the viewer (studs at Scale 1).
-- Balls, relative to the cluster centre: { x, y, z, diameter, top }. Top balls stay
-- round and crumble last; the others squash into the base pile.
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
	for _, key in { "Starburst", "SpotsRed", "Lava", "LavaCracks", "RadialDust", "BallBand" } do
		add(ASSETS[key])
	end
	for _, id in ASSETS.Ash do
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

-- Template for the shell chips (never parented; MeshParticles clones it)
local function chipTemplate(name, color)
	local template = meshFolder and meshFolder:FindFirstChild(name)
	local part = if template then template:Clone() else Instance.new("Part")
	if not template then
		part.Size = Vector3.new(1, 0.25, 1)
	end
	return setupPart(part, Enum.Material.Neon, color, 0.35) -- dark Neon renders flat and unlit
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
	AshColor = Color3.fromRGB(125, 118, 112), -- ash flakes (fading to charcoal)
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
	TopDelay = 0.22, -- seconds the top balls hold their spotted orange look before cooling
	SinkTime = 0.62, -- seconds when the lower balls have squashed into the base pile
	BaseCrumbleStart = 0.9, -- seconds when the base pile starts crumbling to ash
	BaseCrumbleTime = 0.3, -- seconds the base pile takes to crumble
	CrumbleStart = 1.1, -- seconds when the top balls start crumbling to ash
	CrumbleTime = 0.5, -- seconds the top balls take to crumble
	CometCount = 3, -- 0-3 fire comets
	CometSpeed = 28, -- studs/s
	CometGravity = 15, -- studs/s^2 (a slight droop)
	CometTime = 1.6, -- seconds a comet flies before it is removed
	SparkCount = 45,
	DomeSize = 9, -- studs, final half-width of the shock dome
	BaseSize = 9.3, -- studs, width of the area over the base pile that embers and ash rise from
	CrackSize = 4.3, -- studs, half-width of the lava-crack texture (the network fills ~80% of it)
	CrackStart = 0.78, -- seconds when the cracks appear
	CrackTime = 2.8, -- seconds the cracks glow
	EmberRate = 40, -- embers per second while the balls cool and crumble
	WispRate = 7, -- smoke wisps per second rising off the cracks
	ChipCount = 16, -- shell chips shed while the base and balls crumble
	AshRate = 70, -- ash flakes per second while something crumbles
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
	local baseCrumbleStart = p.BaseCrumbleStart
	local baseCrumbleEnd = baseCrumbleStart + p.BaseCrumbleTime

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
			-- top balls tumble their spot pattern freely; base balls only turn about Y, since
			-- they squash along Y (a tilted squashed shell would poke out of the body)
			Spin = if b[5]
				then CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
				else CFrame.Angles(0, math.random() * 6.28, 0),
			SpinRate = (math.random() - 0.5) * 0.8, -- radians/s, slow tumble of the pattern
			Body = newMesh(ctx, "SmoothSphere", Enum.Material.Neon, p.HotColor, 1),
			Spots = newMesh(ctx, "SmoothSphere", Enum.Material.Neon, WHITE, 1, ASSETS.SpotsRed),
			-- outer shell: lava patches on the top balls, the glowing band on the base balls;
			-- it becomes the ash shell when the ball crumbles
			Shell = newMesh(ctx, "SmoothSphere", Enum.Material.Neon, WHITE, 1, if b[5] then ASSETS.Lava else ASSETS.BallBand),
			Att = att,
			Rim = rim,
			Stage = 0,
			IsMesh = hasSphere, -- false: plain Ball fallbacks, the textured shells stay hidden
		})
	end

	-- the cluster bursts out of a small core in ~0.03 s (balls grow and fly apart to their
	-- places), then keeps swelling slowly
	local sizeKeys = { { appear, 0.2 }, { appear + 0.03, 0.85 }, { 0.12, 0.96 }, { 0.2, 1 }, { 0.42, 1.06 }, { crumbleEnd, 1.12 } }
	local spreadKeys = { { appear, 0.3 }, { appear + 0.03, 0.9 }, { 0.12, 1 } }
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
	local bandAlpha = { { 0.42, 1 }, { 0.5, 0.02 } } -- base balls' band shell, effect time
	local sinkKeys = { { 0.42, 0 }, { sinkT, 1 } }
	-- shell texture while crumbling: Ash[1..n] over the crumble, k = 0..1
	local function ashTexture(k)
		return ASSETS.Ash[math.clamp(1 + math.floor(k * #ASSETS.Ash), 1, #ASSETS.Ash)]
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

	-- 5. Cracks, ash, embers, wisps, chips -----------------------------------------------
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

	-- embers rise from just above the base pile (inside the opaque balls they'd be hidden)
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
	-- ash flakes drifting up off whatever is crumbling (the base pile, then the top balls)
	local ashLow = ctx.Anchor(frame * CFrame.new(0, 1.2 * s, 0.3 * s))
	ashLow.Size = Vector3.new(p.BaseSize * s * 0.8, 1.6 * s, p.BaseSize * s * 0.5)
	local ashHigh = ctx.Anchor(center * CFrame.new(0, 2.2 * ballScale, -0.7 * ballScale))
	ashHigh.Size = Vector3.new(6 * ballScale, 2.6 * ballScale, 2.5 * ballScale)
	local ashProps = {
		Texture = ASSETS.Speck,
		Color = colors({ { 0, p.AshColor }, { 1, p.AshColor:Lerp(Color3.new(), 0.6) } }),
		LightEmission = 0,
		Shape = Enum.ParticleEmitterShape.Box,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(40, 40),
		Speed = NumberRange.new(1 * s, 3 * s),
		Drag = 1,
		Acceleration = Vector3.new(0.6 * s, 1.5 * s, 0), -- float up and drift aside
		Lifetime = NumberRange.new(0.8, 1.4),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-180, 180),
		Size = seq({ { 0, 0.3 * s }, { 0.6, 0.22 * s }, { 1, 0 } }),
		Transparency = seq({ { 0, 0.05 }, { 0.7, 0.25 }, { 1, 1 } }),
	}
	local ashLowE = emitter(ashLow, ashProps)
	local ashHighE = emitter(ashHigh, ashProps)
	local chipColor = Color3.fromRGB(26, 22, 22) -- charcoal (Neon reads brighter than its colour)
	local chipTemplates = { chipTemplate("ShellShard1", chipColor), chipTemplate("ShellShard2", chipColor) }
	local function shedChips(origin, count, size)
		for k, template in chipTemplates do
			MeshParticles.Burst(ctx, template, math.ceil(count / #chipTemplates), {
				Origin = origin,
				Direction = Vector3.yAxis,
				Spread = 70,
				Speed = NumberRange.new(2 * s, 6 * s),
				Lifetime = NumberRange.new(0.5, 0.8),
				Drag = 1.5,
				Acceleration = Vector3.new(0, -10 * s, 0),
				SpinSpeed = NumberRange.new(90, 270),
				Scale = size * (0.8 + 0.3 * k),
				SpawnRadius = 1.5 * s,
				Size = seq({ { 0, 1 }, { 0.7, 0.8 }, { 1, 0 } }),
				Transparency = seq({ { 0, 0.35 }, { 0.7, 0.5 }, { 1, 1 } }),
			})
		end
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
	local emberAcc, wispAcc, ashLowAcc, ashHighAcc = 0, 0, 0, 0
	local endT = math.max(crumbleEnd, baseCrumbleEnd, cometLaunch + p.CometTime, crackStart + crackLife * 0.75)
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
		if once("baseChips", baseCrumbleStart + 0.05, t) then
			shedChips((frame * CFrame.new(0, 1.2 * s, 0)).Position, p.ChipCount * 0.5, 1.1 * s)
		end
		if once("ballChips", crumbleStart + 0.1, t) then
			shedChips(center.Position + Vector3.new(0, 1.6 * ballScale, 0), p.ChipCount * 0.5, 1.4 * ballScale)
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
			local squash = Vector3.one
			local cStart, cTime = crumbleStart, p.CrumbleTime
			if ball.Top then
				offset -= Vector3.new(0, 0.85 * ballScale * sink, 0) -- settle onto the pile
			else
				-- lower balls squash into a lumpy pile resting on the ground
				squash = Vector3.new(1 + 0.1 * sink, 1 - 0.3 * sink, 1 + 0.1 * sink)
				local restY = -center.Position.Y + ground.Y + d * 0.5 * squash.Y * 0.85
				-- and huddle together a little
				offset = Vector3.new(offset.X * (1 - 0.15 * sink), offset.Y + (restY - offset.Y) * sink, offset.Z * (1 - 0.15 * sink))
				cStart, cTime = baseCrumbleStart, p.BaseCrumbleTime
			end
			local k = (t - cStart) / cTime -- crumble progress
			local crumbling = k >= 0
			local gone = k >= 1
			local cf = center * CFrame.new(offset)
			local spinCf = cf * ball.Spin * CFrame.Angles(0, ball.SpinRate * t, 0)
			local uprightCf = cf * CFrame.Angles(0, ball.SpinRate * t, 0)
			local sizeV = squash * d
			ball.Body.Size = sizeV * 0.985
			ball.Body.CFrame = cf
			ball.Body.Color = track(bodyKeys, bt)
			-- crumbling: the solid core goes quickly so the shell's ash holes show through
			ball.Body.Transparency = if t < appear or gone then 1 elseif crumbling then math.min(1, 0.3 + 2.5 * k) else 0
			ball.Spots.Size = sizeV
			ball.Spots.CFrame = spinCf
			ball.Spots.Transparency = if crumbling or not ball.IsMesh then 1 else track(spotsAlpha, bt)
			ball.Shell.Size = sizeV * 1.004
			if not ball.IsMesh then
				ball.Shell.Transparency = 1
			elseif crumbling then
				-- the shell turns to ash: held upright so its holes eat the ball bottom-up
				ball.Shell.CFrame = uprightCf
				local tex = ashTexture(k)
				if ball.Stage ~= tex then
					ball.Stage = tex
					ball.Shell.TextureID = tex
				end
				ball.Shell.Transparency = if gone then 1 else 0.02 + 0.4 * k
			elseif ball.Top then
				ball.Shell.CFrame = spinCf
				ball.Shell.Transparency = track(lavaAlpha, bt)
			else
				ball.Shell.CFrame = cf -- upright, so the bands of neighbouring balls line up
				ball.Shell.Transparency = track(bandAlpha, t)
			end
			ball.Att.WorldPosition = cf.Position
			ball.Rim.Color = ColorSequence.new(track(rimColorKeys, bt))
			ball.Rim.Size = NumberSequence.new(d * 0.5 * track(rimSizeKeys, bt))
			-- squashing balls lose their rim first (a round ring would not fit them)
			local rimAlpha = track(rimAlphaKeys, bt)
			local sinkFade = if ball.Top then 0 else math.clamp(sink * 1.6, 0, 1)
			ball.Rim.Transparency = NumberSequence.new(if crumbling then 1 else rimAlpha + (1 - rimAlpha) * sinkFade)
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

		local dt = ctx.Wait(1 / 60)
		t += dt

		-- embers while the balls cool and crumble (thinning out by ~1.8 s), wisps off the cracks
		if t >= 0.3 and t < 1.8 then
			emberAcc += p.EmberRate * dt * (if t < 0.7 then 0.3 elseif t > 1.4 then 0.5 else 1)
		end
		if t >= 1.4 then
			wispAcc += p.WispRate * dt
		end
		-- ash flakes while the base pile, then the top balls, crumble
		if t >= baseCrumbleStart and t < baseCrumbleEnd then
			ashLowAcc += p.AshRate * dt
		end
		if t >= crumbleStart and t < crumbleEnd then
			ashHighAcc += p.AshRate * dt
		end
		emberAcc = drain(ctx, embers, emberAcc)
		wispAcc = drain(ctx, wisps, wispAcc)
		ashLowAcc = drain(ctx, ashLowE, ashLowAcc)
		ashHighAcc = drain(ctx, ashHighE, ashHighAcc)
	end
end

return Effect
