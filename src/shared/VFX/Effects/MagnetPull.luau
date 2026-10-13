-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/MagnetPull
-- Purple gravity suction: everything around a point is pulled into it. Layers:
-- implosion pulses (a translucent dome and a ground disc that snap in big and
-- shrink into the centre, several times a second), dark glass shards and specks
-- pulled inward, flickering lilac lightning and black jagged streaks, thin
-- vertical magenta/black lines, a violet ground haze and a pulsing light.
-- With BlackHole on: a star glint opens it, then a dark swirling core with bright
-- arcs and a neon ring sits in the centre, swallowing everything.
--
-- ctx.CFrame: the pull centre. The effect sits on the ground below it.
-- Runs for Duration seconds (after the glint), then everything still flying
-- finishes and fades.
--
-- The dome is a camera-facing shell particle centred on the ground: the ground
-- hides its lower half, so it reads as a dome standing on the disc.
-- Scattered layers emit from invisible shaped parts (Box volume for the flickers,
-- an upper-hemisphere surface with ShapeInOut Inward for the specks): moving an
-- Attachment between Emit calls in one frame does not move the spawn point.

local VFX = script.Parent.Parent
local MeshParticles = require(VFX:WaitForChild("MeshParticles"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	SphereShell = "rbxassetid://135297534254471", -- StaticVFXTextures/Sphere_Mask_02
	GlowDisc = "rbxassetid://13580366694", -- StaticVFXTextures/glowing ring (filled disc, bright soft rim)
	BandRing = "rbxassetid://15058135927", -- StaticVFXTextures/thick ring 2 (soft medium band)
	NeonRing = "rbxassetid://15268062056", -- StaticVFXTextures/thick ring 3 (crisp inner edge, soft glow)
	CoreSwirl = "rbxassetid://17612139917", -- FlipbookTextures/Whole swirl (Grid4x4): wispy strands circling a core
	Smoke = "rbxassetid://111394301752764", -- StaticVFXTextures/smoke 41
	Crescent32 = "rbxassetid://17388445727", -- StaticVFXTextures/Crescent32 (layered crescent strokes)
	SoftGlow = "rbxassetid://284205403", -- StaticVFXTextures/Blurred Spec 11
	Bolt = "rbxassetid://137202180073755", -- FlipbookTextures/Lightning Scribble 4x4 (Grid4x4)
	BlackEnergy = "rbxassetid://17511030724", -- FlipbookTextures/Glowing Black Energy (Grid4x4)
	Needle = "rbxassetid://10614304526", -- StaticVFXTextures/Sideways Spec 41
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	CoreRipple = "rbxassetid://13826100764", -- FlipbookTextures/Blackhole Ripple (Grid4x4): black core, swirling rim
	CoreArcs = "rbxassetid://73527526679754", -- FlipbookTextures/Blackhole spec (Grid4x4): bright arcs
	CoreShadow = "rbxassetid://107972524433656", -- StaticVFXTextures/Blurry Black Hole
	StarRays = "rbxassetid://17391818367", -- StaticVFXTextures/Star102
}

local WHITE = Color3.new(1, 1, 1)

--------------------------------------------------------------------------------
-- helpers

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

-- Ground point under the centre, skipping characters and non-collidable parts
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

-- Dark slab and cube templates for the MeshParticles shards (never parented; built
-- per play so overlapping plays with different sizes/colours don't fight). Neon with
-- a dark colour renders flat and unlit, so sunlit faces don't turn grey.
local function makeShardTemplates(color)
	local templates = {}
	for _ = 1, 2 do
		local part = Instance.new("Part")
		part.Name = "Shard"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = color
		table.insert(templates, part)
	end
	return templates
end

--------------------------------------------------------------------------------

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(100, 75, 255), -- blue-violet dome
	FillColor = Color3.fromRGB(50, 20, 190), -- dark violet fill inside the ground disc (contrast for the band)
	DiscColor = Color3.fromRGB(205, 80, 245), -- bright magenta band around the disc
	RingColor = Color3.fromRGB(240, 130, 255), -- thin neon ring the band closes into
	HazeColor = Color3.fromRGB(80, 25, 255), -- violet ground glow under the pull
	BoltColor = Color3.fromRGB(220, 95, 255), -- pink-lilac lightning strands
	LineColor = Color3.fromRGB(210, 45, 255), -- thin magenta lines and specks
	InkColor = Color3.fromRGB(14, 8, 24), -- black jagged streaks
	ShardColor = Color3.fromRGB(16, 18, 30),
	Scale = 1,
	Duration = 1.5, -- seconds the pull runs
	Radius = 14, -- studs; pull radius and starting size of each pulse
	PulseInterval = 0.14, -- seconds between implosion pulses
	PulseTime = 0.11, -- seconds for one pulse to shrink into the centre
	BoltRate = 24, -- lightning flickers per second
	InkRate = 18, -- black jagged streaks per second
	LineRate = 22, -- thin vertical lines per second (half magenta, half black)
	SpeckRate = 30, -- specks pulled inward per second
	SpeckTime = 0.3, -- seconds for a speck to fly from the edge to the centre
	WispRate = 18, -- pale smoke wisps drawn into the dome per second
	StreakRate = 16, -- faint violet streaks skating inward across the ground per second
	ShardCount = 20, -- shards pulled in over Duration
	CaughtShardCount = 5, -- shards already caught in the pull at the start
	ShardSize = 5, -- studs
	ShardPull = 40, -- studs/s^2 inward acceleration of the shards
	LightBrightness = 3,
	BlackHole = true, -- dark core in the centre (false = suction only)
	CoreSize = 2.2, -- studs, core radius
	CoreColor = Color3.fromRGB(75, 50, 200), -- tint on the core's swirling rim (dark)
	CoreShadowColor = Color3.fromRGB(15, 5, 40), -- dark halo behind the core
	CoreBallColor = Color3.fromRGB(14, 8, 40), -- the solid dark ball at the centre
	CoreSpinSpeed = 600, -- degrees/s of the spinning ring strokes around the core
	CoreRingColor = Color3.fromRGB(235, 110, 255), -- faint pink ring at the core's base
	ArcColor = Color3.fromRGB(185, 140, 255), -- violet arcs and wisps hugging the core
	FlashSize = 11, -- studs, half-width of the opening star glint
	FlashTime = 0.25, -- seconds; the pull starts 60% of the way through (0 = no glint)
}

Effect.Linger = 1.1 -- longest shard lifetime (1.05) + margin

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local radius = p.Radius * s

	local ground = findGround(ctx)
	local anchor = ctx.Anchor(CFrame.new(ground))
	local center = Instance.new("Attachment")
	center.Parent = anchor

	-- 0. Opening star glint (black hole only): grows, spins and snaps shut ------
	if p.BlackHole and p.FlashTime > 0 then
		local flashSize = p.FlashSize * s
		local glint = Instance.new("Attachment")
		glint.Position = Vector3.new(0, 1 * s, 0)
		glint.Parent = anchor
		local star = emitter(glint, {
			Texture = ASSETS.StarRays,
			Speed = NumberRange.new(0),
			Lifetime = NumberRange.new(p.FlashTime),
			-- Star102 is an X of rays; around -15 it sits as a "+". Spinning from +20
			-- it passes through "+" near its peak.
			Rotation = NumberRange.new(15, 25),
			RotSpeed = NumberRange.new(-240),
			LightEmission = 0.5, -- keeps the violet on bright ground
			Brightness = 1.6,
			ZOffset = 3,
			Color = colors({
				{ 0, Color3.fromRGB(215, 170, 255) },
				{ 0.5, Color3.fromRGB(165, 95, 255) },
				{ 1, Color3.fromRGB(120, 60, 230) },
			}),
			Size = seq({ { 0, flashSize * 0.2 }, { 0.2, flashSize }, { 0.5, flashSize * 0.4 }, { 0.8, 0 }, { 1, 0 } }), -- gone before the core appears
			Transparency = seq({ { 0, 0 }, { 0.8, 0 }, { 1, 0.5 } }),
		})
		ctx.Emit(star, 1)
		ctx.Wait(p.FlashTime * 0.6)
	end

	-- 1. Implosion pulse layers ------------------------------------------------
	-- Shrink curve shared by the dome and the disc: a faint oversized first frame,
	-- snaps to full size, then collapses (fast first, slowing near the centre)
	local function shrink(size)
		return seq({
			{ 0, size * 1.25 },
			{ 0.12, size },
			{ 0.25, size * 0.8 },
			{ 0.4, size * 0.63 },
			{ 0.55, size * 0.5 },
			{ 0.7, size * 0.42 },
			{ 0.85, size * 0.35 },
			{ 1, size * 0.3 },
		})
	end
	local pulseLife = NumberRange.new(p.PulseTime)
	local dome = emitter(center, {
		Texture = ASSETS.GlowDisc,
		Lifetime = pulseLife,
		Speed = NumberRange.new(0),
		LightEmission = 0.15,
		ZOffset = 0.5,
		Color = ColorSequence.new(p.Color),
		Size = shrink(radius * 0.85),
		-- the fill fades as it closes in, handing over to the rim below
		Transparency = seq({ { 0, 0.85 }, { 0.12, 0.1 }, { 0.6, 0.3 }, { 0.9, 0.6 }, { 1, 1 } }),
	})
	local domeRim = emitter(center, {
		Texture = ASSETS.SphereShell,
		Lifetime = pulseLife,
		Speed = NumberRange.new(0),
		LightEmission = 0.4,
		ZOffset = 0.55,
		Color = ColorSequence.new(p.Color:Lerp(WHITE, 0.3)),
		Size = shrink(radius * 0.87),
		Transparency = seq({ { 0, 0.85 }, { 0.12, 0.15 }, { 0.6, 0 }, { 0.9, 0 }, { 1, 1 } }),
	})
	-- Ground disc: violet fill that fades out as it shrinks, leaving the band
	-- around its edge as a bright closing ring
	local function flatPulse(props)
		props.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		props.EmissionDirection = Enum.NormalId.Top
		props.Speed = NumberRange.new(0.01)
		props.Lifetime = pulseLife
		return emitter(center, props)
	end
	local disc = flatPulse({
		Texture = ASSETS.GlowDisc,
		LightEmission = 0,
		ZOffset = 0.2,
		Color = ColorSequence.new(p.FillColor),
		Size = shrink(radius * 0.88), -- edge sits under the band: not outside it (navy rim), not inside (double ring)
		Transparency = seq({ { 0, 0.85 }, { 0.12, 0 }, { 0.55, 0.2 }, { 0.85, 1 }, { 1, 1 } }),
	})
	-- The ring at the disc's edge: a soft magenta band while the pulse is big, handing
	-- over to a crisp neon ring as it closes in (the reference's ring sharpens and
	-- brightens as it shrinks). Both sit exactly on the dome's base.
	local discBand = flatPulse({
		Texture = ASSETS.BandRing,
		LightEmission = 0.85, -- high enough that the band's dark outer edge doesn't read navy
		ZOffset = 0.7, -- over the dome's flat base
		Color = ColorSequence.new(p.DiscColor),
		-- the band's centre line sits at ~0.78 of the quad: 1.04 puts it on the dome's base
		Size = shrink(radius * 1.04),
		Transparency = seq({ { 0, 0.85 }, { 0.12, 0 }, { 0.5, 0.05 }, { 0.8, 0.6 }, { 1, 1 } }),
	})
	-- A second, slightly smaller copy widens the band to ~25% of the radius
	local discBandInner = flatPulse({
		Texture = ASSETS.BandRing,
		LightEmission = 0.3, -- overlaps the outer copy: more additive here blows out to white
		ZOffset = 0.69,
		Color = ColorSequence.new(p.DiscColor),
		Size = shrink(radius * 0.94),
		Transparency = seq({ { 0, 0.85 }, { 0.12, 0 }, { 0.5, 0.05 }, { 0.8, 0.6 }, { 1, 1 } }),
	})
	local thinRing = flatPulse({
		Texture = ASSETS.NeonRing,
		LightEmission = 1,
		Brightness = 1.6,
		ZOffset = 0.75,
		Color = ColorSequence.new(p.RingColor),
		Size = shrink(radius * 1.08), -- ring at ~0.75 of the quad
		-- a faint crisp edge on the band at the peak, fully bright as it closes
		Transparency = seq({ { 0, 1 }, { 0.12, 0.75 }, { 0.35, 0.6 }, { 0.6, 0.2 }, { 0.85, 0 }, { 1, 1 } }),
	})

	-- 2. Ground haze, held for the whole pull ------------------------------------
	local haze = emitter(center, {
		Texture = ASSETS.SoftGlow,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01),
		Lifetime = NumberRange.new(p.Duration + 0.3),
		LightEmission = 1,
		Color = ColorSequence.new(p.HazeColor),
		Size = NumberSequence.new(radius * 0.9),
		Transparency = seq({ { 0, 1 }, { 0.1, 0.45 }, { 0.85, 0.5 }, { 1, 1 } }),
	})
	ctx.Emit(haze, 1)

	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = math.min(20, radius * 1.6)
	light.Brightness = 0
	light.Parent = center

	-- 3. Flickers: lightning, black jagged streaks, thin lines -------------------
	-- A box volume around the centre, from the ground up past the dome
	local flickerBox = ctx.Anchor(CFrame.new(ground + Vector3.new(0, 4.5 * s, 0)))
	flickerBox.Size = Vector3.new(radius * 2.2, 9 * s, radius * 2.2)
	local function flicker(props)
		props.Shape = Enum.ParticleEmitterShape.Box
		props.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		props.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp -- stay vertical
		return emitter(flickerBox, props)
	end
	local bolts = flicker({
		Texture = ASSETS.Bolt,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(1 * s, 3 * s),
		Lifetime = NumberRange.new(0.05, 0.09),
		Rotation = NumberRange.new(-8, 8),
		LightEmission = 0.5, -- half additive: glows but stays pink on bright ground
		Brightness = 2.2,
		ZOffset = 1,
		Color = ColorSequence.new(p.BoltColor),
		Size = seq({ { 0, 3.2 * s, 0.5 * s }, { 1, 3 * s, 0.4 * s } }),
		Squash = NumberSequence.new(0.7), -- tall clusters
		Transparency = seq({ { 0, 0 }, { 0.7, 0.1 }, { 1, 1 } }),
	})
	local ink = flicker({
		Texture = ASSETS.BlackEnergy,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(1 * s, 3 * s),
		Lifetime = NumberRange.new(0.06, 0.11),
		Rotation = NumberRange.new(-4, 4),
		LightEmission = 0,
		ZOffset = 0.9,
		Color = ColorSequence.new(p.InkColor),
		Size = seq({ { 0, 2.3 * s, 0.3 * s }, { 1, 2.1 * s, 0.3 * s } }),
		Squash = NumberSequence.new(1.4), -- tall, narrow jagged streaks
		Transparency = seq({ { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } }),
	})
	local function line(color, size, zOffset)
		return flicker({
			Texture = ASSETS.Needle,
			EmissionDirection = Enum.NormalId.Bottom,
			Speed = NumberRange.new(4 * s, 8 * s),
			Lifetime = NumberRange.new(0.1, 0.18),
			LightEmission = 0, -- normal blend keeps the magenta saturated on bright ground
			ZOffset = zOffset,
			Color = ColorSequence.new(color),
			Size = seq({ { 0, size * s, 0.4 * s }, { 1, (size - 0.2) * s, 0.4 * s } }),
			Squash = NumberSequence.new(0.6), -- long and hair-thin
			Transparency = seq({ { 0, 0.05 }, { 0.7, 0.1 }, { 1, 1 } }),
		})
	end
	local glowLines = line(p.LineColor, 3.6, 1)
	local inkLines = line(Color3.new(0, 0, 0), 3.4, 0.9)

	-- 4. Specks pulled inward from an upper hemisphere ----------------------------
	local speckShell = ctx.Anchor(CFrame.new(ground))
	speckShell.Size = Vector3.one * radius * 2.2
	local speckTime = p.SpeckTime
	local speckSpeed = radius * 1.1 / speckTime
	local function speckEmitter(color, zOffset)
		return emitter(speckShell, {
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			ShapePartial = 0.5, -- upper half only
			Speed = NumberRange.new(speckSpeed),
			Lifetime = NumberRange.new(speckTime * 0.7, speckTime * 0.95), -- gone before the centre
			Texture = ASSETS.Speck,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-300, 300),
			LightEmission = 0,
			ZOffset = zOffset,
			Color = ColorSequence.new(color),
			Size = seq({ { 0, 0 }, { 0.2, 0.18 * s, 0.05 * s }, { 0.8, 0.15 * s }, { 1, 0 } }),
		})
	end
	local purpleSpecks = speckEmitter(p.LineColor:Lerp(Color3.new(0, 0, 0), 0.15), 1)
	local darkSpecks = speckEmitter(Color3.fromRGB(10, 8, 16), 0.8)
	-- Pale wisps of smoke drawn in from the dome's edge, shrinking as they go
	local wispSmoke = emitter(speckShell, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapePartial = 0.5,
		Speed = NumberRange.new(speckSpeed * 0.8),
		Lifetime = NumberRange.new(speckTime * 0.8, speckTime * 1.1),
		Texture = ASSETS.Smoke,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		LightEmission = 0.5,
		ZOffset = 0.65,
		Color = ColorSequence.new(p.ArcColor:Lerp(p.Color, 0.5)),
		Size = seq({ { 0, 2.5 * s }, { 1, 0.4 * s } }),
		Transparency = seq({ { 0, 1 }, { 0.25, 0.75 }, { 0.75, 0.8 }, { 1, 1 } }),
	})

	-- Ground streaks: thin lines skating inward across the floor
	local floorRing = ctx.Anchor(CFrame.new(ground + Vector3.new(0, 0.15 * s, 0)))
	-- A Sphere shape on a flattened part is an ellipse on the floor; Inward then sends
	-- particles radially toward the centre (Disc/Cylinder shapes don't, see structure.md)
	floorRing.Size = Vector3.new(radius * 2.4, 0.2, radius * 2.4)
	local floorStreaks = emitter(floorRing, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Speed = NumberRange.new(speckSpeed),
		Lifetime = NumberRange.new(speckTime * 0.6, speckTime * 0.85),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Texture = ASSETS.Needle,
		LightEmission = 1,
		ZOffset = 0.3,
		Color = ColorSequence.new(Color3.fromRGB(170, 110, 255)),
		Size = seq({ { 0, 0 }, { 0.2, 2 * s }, { 1, 0.8 * s } }),
		Squash = NumberSequence.new(1.5),
		Transparency = seq({ { 0, 0.5 }, { 0.7, 0.6 }, { 1, 1 } }),
	})

	-- 5. Shards: dark slabs and cubes pulled into the centre ----------------------
	local templates = makeShardTemplates(p.ShardColor)
	local shardSize = p.ShardSize * s
	templates[1].Size = Vector3.new(shardSize, shardSize * 0.22, shardSize * 0.6) -- slab
	templates[2].Size = Vector3.one * shardSize * 0.3 -- cube
	local pullPoint = ground + Vector3.new(0, 1.5 * s, 0)
	local shardIndex = 0
	-- smoky far out, darker as they near the centre
	local shardFade = seq({ { 0, 1 }, { 0.1, 0.7 }, { 0.6, 0.45 }, { 0.9, 0.3 }, { 1, 1 } })
	local shardGrow = seq({ { 0, 0.5 }, { 0.1, 1 }, { 0.6, 0.9 }, { 1, 0 } })
	-- Shards already caught in the pull at the start: visible from the first frame
	local caughtFade = seq({ { 0, 0.6 }, { 0.6, 0.45 }, { 0.9, 0.3 }, { 1, 1 } })
	local caughtGrow = seq({ { 0, 1 }, { 0.6, 0.9 }, { 1, 0 } })
	local function spawnShard(caught)
		shardIndex += 1
		local angle = math.random() * math.pi * 2
		local r = radius * (0.9 + math.random() * 0.5)
		local height = 2.5 + math.random() * (if caught then 6 else 9) -- off the floor so they never read as ground shadows
		local origin = ground + Vector3.new(math.cos(angle) * r, height * s, math.sin(angle) * r)
		local inward = (pullPoint - origin).Unit
		MeshParticles.Burst(ctx, templates[if shardIndex % 3 == 0 then 2 else 1], 1, {
			Origin = origin,
			Direction = inward,
			Spread = 20,
			Speed = NumberRange.new(1 * s, 3 * s),
			Acceleration = inward * p.ShardPull * s,
			SpinSpeed = NumberRange.new(40, 160),
			Scale = 0.6 + math.random() * 0.6,
			Lifetime = NumberRange.new(0.9, 1.05), -- consumed just before reaching the centre
			Size = if caught then caughtGrow else shardGrow,
			Transparency = if caught then caughtFade else shardFade,
		})
	end

	-- 6. Black hole core: held for the whole pull, arcs flash with each pulse ----
	local coreArcs, coreBallShrink
	if p.BlackHole then
		local core = p.CoreSize * s
		-- raised so the ground cuts only its bottom: reads as a ball sitting in the ring
		local ball = Instance.new("Attachment")
		ball.Position = Vector3.new(0, core * 0.5, 0)
		ball.Parent = anchor
		local coreLife = NumberRange.new(p.Duration + 0.25)
		-- grows in over ~0.07 s, holds, collapses at the very end
		local function held(size)
			return seq({ { 0, 0 }, { 0.04, size }, { 0.9, size }, { 1, 0 } })
		end
		local shadow = emitter(ball, {
			Texture = ASSETS.CoreShadow,
			Speed = NumberRange.new(0),
			Lifetime = coreLife,
			LightEmission = 0,
			ZOffset = 1.1,
			Color = ColorSequence.new(p.CoreShadowColor),
			Size = held(core * 1.6),
		})
		local ripple = emitter(ball, {
			Texture = ASSETS.CoreRipple,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
			FlipbookMode = Enum.ParticleFlipbookMode.Loop,
			FlipbookFramerate = NumberRange.new(24),
			Speed = NumberRange.new(0),
			Lifetime = coreLife,
			LightEmission = 0,
			ZOffset = core * 0.8, -- in front of the dark ball's near side
			Color = ColorSequence.new(p.CoreColor),
			Size = held(core * 1.1),
		})
		-- A solid dark ball inside the flipbook core: bold and fully opaque. Dark Neon
		-- renders flat and unlit; the ground hides its lower half.
		local coreBall = Instance.new("Part")
		coreBall.Name = "Core"
		coreBall.Shape = Enum.PartType.Ball
		coreBall.Material = Enum.Material.Neon
		coreBall.Color = p.CoreBallColor
		coreBall.Anchored = true
		coreBall.CanCollide = false
		coreBall.CanQuery = false
		coreBall.CanTouch = false
		coreBall.CastShadow = false
		coreBall.Size = Vector3.one * 0.1
		coreBall.CFrame = anchor.CFrame * CFrame.new(0, core * 0.5, 0)
		coreBall.Parent = ctx.Folder
		ctx.Tween(coreBall, 0.07, { Size = Vector3.one * core * 1.35 })
		-- A tight neon ring hugging the ball's base (not a wide halo)
		local coreRing = flatPulse({
			Texture = ASSETS.NeonRing,
			LightEmission = 1,
			Brightness = 1.2,
			ZOffset = 1.5, -- over the disc band
			Color = ColorSequence.new(p.CoreRingColor),
			-- just inside where each closing pulse ring ends, so the two don't double up
			Size = held(core * 2),
			Transparency = seq({ { 0, 1 }, { 0.04, 0.45 }, { 0.9, 0.45 }, { 1, 1 } }),
		})
		coreRing.Lifetime = coreLife
		-- White-violet wisps circling the ball; two copies spinning opposite ways
		local swirl = emitter(ball, {
			Texture = ASSETS.CoreSwirl,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
			FlipbookMode = Enum.ParticleFlipbookMode.Loop,
			FlipbookFramerate = NumberRange.new(20),
			Speed = NumberRange.new(0),
			Lifetime = coreLife,
			Rotation = NumberRange.new(0, 360),
			LightEmission = 1,
			Brightness = 1.3,
			ZOffset = core + 0.5,
			Color = ColorSequence.new(p.ArcColor),
			Size = held(core * 1.6),
			Transparency = seq({ { 0, 1 }, { 0.04, 0.25 }, { 0.9, 0.25 }, { 1, 1 } }),
		})
		ctx.Emit(shadow, 1)
		ctx.Emit(ripple, 1)
		ctx.Emit(coreRing, 1)
		swirl.RotSpeed = NumberRange.new(p.CoreSpinSpeed)
		ctx.Emit(swirl, 1)
		swirl.RotSpeed = NumberRange.new(-p.CoreSpinSpeed * 0.75)
		ctx.Emit(swirl, 1)
		-- Crescent strokes lying flat around the core's base, spinning fast: the ring
		-- around the hole visibly turns (a plain ring texture can't show rotation)
		local spinRing = flatPulse({
			Texture = ASSETS.Crescent32,
			LightEmission = 1,
			Brightness = 1.5,
			ZOffset = 1.55,
			Color = ColorSequence.new(p.CoreRingColor),
			Rotation = NumberRange.new(0, 360),
			Size = held(core * 1.9),
			Transparency = seq({ { 0, 1 }, { 0.04, 0.15 }, { 0.9, 0.15 }, { 1, 1 } }),
		})
		spinRing.Lifetime = coreLife
		spinRing.RotSpeed = NumberRange.new(p.CoreSpinSpeed * 1.2)
		ctx.Emit(spinRing, 2)
		coreArcs = emitter(ball, {
			Texture = ASSETS.CoreArcs,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
			FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
			Speed = NumberRange.new(0),
			Lifetime = NumberRange.new(p.PulseInterval * 1.2),
			Rotation = NumberRange.new(-70, 70),
			LightEmission = 1,
			Brightness = 1.3,
			ZOffset = core + 0.4,
			Color = ColorSequence.new(p.ArcColor),
			Size = seq({ { 0, core * 1.25, core * 0.15 }, { 1, core * 1.1, core * 0.1 } }),
			Transparency = seq({ { 0, 0 }, { 0.7, 0.15 }, { 1, 1 } }),
		})
		light.Range = math.min(20, light.Range * 1.2)
		coreBallShrink = function()
			ctx.Tween(coreBall, 0.2, { Size = Vector3.one * 0.1, Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end

	-- 7. Timeline ---------------------------------------------------------------
	local rates = {
		{ bolts, p.BoltRate },
		{ ink, p.InkRate },
		{ glowLines, p.LineRate / 2 },
		{ inkLines, p.LineRate / 2 },
		{ purpleSpecks, p.SpeckRate * 0.6 },
		{ darkSpecks, p.SpeckRate * 0.4 },
		{ wispSmoke, p.WispRate },
		{ floorStreaks, p.StreakRate },
	}
	if p.BlackHole then -- the hole tears open with a ring of bolts and black streaks
		ctx.Emit(bolts, 8)
		ctx.Emit(ink, 3)
	end
	local owed = {}
	for i in rates do
		owed[i] = math.random() -- random phase so the layers don't all fire on frame 1
	end
	for _ = 1, p.CaughtShardCount do -- debris already caught, so the start isn't empty
		spawnShard(true)
	end
	local shardEvery = p.Duration / math.max(p.ShardCount, 1)
	local nextPulse, nextShard = 0, shardEvery
	local elapsed, dt = 0, 0
	while elapsed < p.Duration and ctx.Folder.Parent do
		if elapsed >= nextPulse then
			nextPulse += p.PulseInterval
			ctx.Emit(dome, 2) -- two overlapping copies: the texture's fill is faint
			ctx.Emit(domeRim, 1)
			ctx.Emit(disc, 2)
			ctx.Emit(discBand, 1)
			ctx.Emit(discBandInner, 1)
			ctx.Emit(thinRing, 1)
			if coreArcs then
				ctx.Emit(coreArcs, 2) -- two random tilts so the arcs cross
			end
			light.Brightness = p.LightBrightness * 1.5
			ctx.Tween(light, p.PulseInterval, { Brightness = p.LightBrightness * 0.4 })
		end
		if p.ShardCount > 0 and elapsed >= nextShard then
			nextShard += shardEvery
			spawnShard(false)
		end
		for i, rate in rates do
			owed[i] += rate[2] * dt
			local count = math.floor(owed[i])
			if count > 0 then
				owed[i] -= count
				ctx.Emit(rate[1], count)
			end
		end
		-- ctx.Wait returns the effect time that really passed (a 1/60 wait often
		-- takes two frames); counting 1/60 per loop would stretch every interval
		dt = ctx.Wait(1 / 60)
		elapsed += dt
	end
	ctx.Tween(light, 0.3, { Brightness = 0 })
	if coreBallShrink then
		coreBallShrink()
	end
end

return Effect
