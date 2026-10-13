-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/MagnetPull
-- Purple gravity suction: everything around a point is pulled into it. Layers:
-- implosion pulses (a translucent dome and a ground disc that snap in big and
-- shrink into the centre, several times a second), dark glass shards and specks
-- pulled inward, flickering lilac lightning and black jagged streaks, thin
-- vertical magenta/black lines, a violet ground haze and a pulsing light.
--
-- ctx.CFrame: the pull centre. The effect sits on the ground below it.
-- Runs for Duration seconds, then everything still flying finishes and fades.
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
	ThickRing = "rbxassetid://70800352387937", -- StaticVFXTextures/Ring_Thick_001
	ThinRing = "rbxassetid://12946041355", -- StaticVFXTextures/glowing ring 2
	WispySphere = "rbxassetid://115949955697406", -- FlipbookTextures/Wispy Sphere 4x4 (Grid4x4)
	SoftGlow = "rbxassetid://284205403", -- StaticVFXTextures/Blurred Spec 11
	Bolt = "rbxassetid://137202180073755", -- FlipbookTextures/Lightning Scribble 4x4 (Grid4x4)
	BlackEnergy = "rbxassetid://17511030724", -- FlipbookTextures/Glowing Black Energy (Grid4x4)
	Needle = "rbxassetid://10614304526", -- StaticVFXTextures/Sideways Spec 41
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
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

-- Dark slabs and small cubes used as MeshParticles shards. Neon with a dark colour
-- renders flat and unlit, so sunlit faces don't turn grey.
local shardTemplates
local function getShardTemplates()
	if not shardTemplates then
		shardTemplates = {}
		for _ = 1, 2 do
			local part = Instance.new("Part")
			part.Name = "Shard"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.Neon
			table.insert(shardTemplates, part)
		end
	end
	return shardTemplates
end

--------------------------------------------------------------------------------

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(100, 75, 255), -- blue-violet dome
	FillColor = Color3.fromRGB(70, 35, 235), -- violet fill inside the ground disc
	DiscColor = Color3.fromRGB(185, 85, 255), -- band around the disc
	RingColor = Color3.fromRGB(240, 130, 255), -- thin neon ring the band closes into
	HazeColor = Color3.fromRGB(80, 25, 255), -- violet ground glow under the pull
	BoltColor = Color3.fromRGB(220, 95, 255), -- pink-lilac lightning strands
	LineColor = Color3.fromRGB(210, 45, 255), -- thin magenta lines and specks
	InkColor = Color3.fromRGB(14, 8, 24), -- black jagged streaks
	ShardColor = Color3.fromRGB(16, 18, 30),
	Scale = 1,
	Duration = 1.5, -- seconds the pull runs
	Radius = 10, -- studs; pull radius and starting size of each pulse
	PulseInterval = 0.17, -- seconds between implosion pulses
	PulseTime = 0.13, -- seconds for one pulse to shrink into the centre
	BoltRate = 18, -- lightning flickers per second
	InkRate = 14, -- black jagged streaks per second
	LineRate = 20, -- thin vertical lines per second (half magenta, half black)
	SpeckRate = 20, -- specks pulled inward per second
	ShardCount = 14, -- shards pulled in over Duration (plus 5 already there at the start)
	ShardSize = 5, -- studs
	ShardPull = 20, -- studs/s^2 inward acceleration of the shards
	LightBrightness = 2,
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
	local wisps = emitter(center, {
		Texture = ASSETS.WispySphere,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Lifetime = pulseLife,
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(-20, 20),
		LightEmission = 1,
		ZOffset = 0.6,
		Color = ColorSequence.new(p.BoltColor),
		Size = shrink(radius * 0.8),
		Transparency = seq({ { 0, 1 }, { 0.12, 0.9 }, { 0.7, 0.93 }, { 1, 1 } }),
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
		Size = shrink(radius * 0.88),
		Transparency = seq({ { 0, 0.85 }, { 0.12, 0 }, { 0.55, 0.2 }, { 0.85, 1 }, { 1, 1 } }),
	})
	local discBand = flatPulse({
		Texture = ASSETS.ThickRing,
		LightEmission = 0.2,
		ZOffset = 0.7, -- over the dome's flat base
		Color = colors({ { 0, p.DiscColor:Lerp(p.FillColor, 0.5) }, { 0.5, p.DiscColor }, { 1, p.DiscColor } }),
		Size = shrink(radius * 0.92),
		Transparency = seq({ { 0, 0.85 }, { 0.12, 0.05 }, { 0.5, 0.05 }, { 0.85, 0.7 }, { 1, 1 } }),
	})
	local thinRing = flatPulse({ -- takes over from the band as the pulse closes in
		Texture = ASSETS.ThinRing,
		LightEmission = 1,
		ZOffset = 0.75,
		Color = ColorSequence.new(p.RingColor),
		Size = shrink(radius * 0.92),
		Transparency = seq({ { 0, 1 }, { 0.35, 1 }, { 0.6, 0.3 }, { 0.85, 0 }, { 1, 1 } }),
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
	local speckTime = 0.45
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

	-- 5. Shards: dark slabs and cubes pulled into the centre ----------------------
	local templates = getShardTemplates()
	local shardSize = p.ShardSize * s
	templates[1].Size = Vector3.new(shardSize, shardSize * 0.22, shardSize * 0.6) -- slab
	templates[2].Size = Vector3.one * shardSize * 0.3 -- cube
	for _, template in templates do
		template.Color = p.ShardColor
	end
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
		local height = 1 + math.random() * (if caught then 6 else 9)
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

	-- 6. Timeline ---------------------------------------------------------------
	local rates = {
		{ bolts, p.BoltRate },
		{ ink, p.InkRate },
		{ glowLines, p.LineRate / 2 },
		{ inkLines, p.LineRate / 2 },
		{ purpleSpecks, p.SpeckRate * 0.6 },
		{ darkSpecks, p.SpeckRate * 0.4 },
	}
	local owed = {}
	for i in rates do
		owed[i] = math.random() -- random phase so the layers don't all fire on frame 1
	end
	if p.ShardCount > 0 then
		for _ = 1, 5 do -- debris already caught in the pull, so the start isn't empty
			spawnShard(true)
		end
	end
	local shardEvery = p.Duration / math.max(p.ShardCount, 1)
	local nextPulse, nextShard = 0, shardEvery
	local elapsed, dt = 0, 0
	while elapsed < p.Duration and ctx.Folder.Parent do
		if elapsed >= nextPulse then
			nextPulse += p.PulseInterval
			ctx.Emit(dome, 2) -- two overlapping copies: the texture's fill is faint
			ctx.Emit(domeRim, 1)
			ctx.Emit(wisps, 1)
			ctx.Emit(disc, 2)
			ctx.Emit(discBand, 1)
			ctx.Emit(thinRing, 1)
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
end

return Effect
