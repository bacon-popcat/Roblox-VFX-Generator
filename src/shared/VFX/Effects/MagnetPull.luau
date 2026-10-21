-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/MagnetPull
-- Purple gravity suction: everything around a point is pulled into it. Layers: implosion
-- pulses (a faint dome and a dark ground disc that snap in big and shrink into the centre,
-- ringed by a magenta band that hands over to a thin hot ring), dark shards, specks, lilac
-- smoke wisps and floor streaks pulled inward, flickering lightning with black jagged twins,
-- thin vertical lines in magenta and black, a ground haze and a light per hue.
-- With BlackHole on: an anticipation (a spiky star and its black twin swell while spinning,
-- then implode to nothing), a pop as the hole opens, and a held core built like an orb:
-- black linework, a hard ring, a black pupil, swirling rays, an outer ring, a soft halo and
-- a black backdrop, every layer cross-fading so the core holds but shimmers.
--
-- Palette: Color (violet), AccentColor (magenta), HighlightColor (pale lilac), DeepColor
-- (dark violet), InkColor (near black). Everything takes one of them.
--
-- ctx.CFrame: the pull centre. The effect sits on the ground below it. The pull runs for
-- Duration seconds (after the anticipation), then everything still flying finishes.
-- The dome is a camera-facing disc centred on the ground: the ground hides its lower half,
-- so it reads as a dome. Scattered layers emit from invisible shaped parts (a Box volume
-- for the flickers, an upper-hemisphere surface with ShapeInOut Inward for the specks).

local VFX = script.Parent.Parent
local MeshParticles = require(VFX:WaitForChild("MeshParticles"))
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	SphereShell = "rbxassetid://135297534254471", -- StaticVFXTextures/Sphere_Mask_02
	GlowDisc = "rbxassetid://13580366694", -- StaticVFXTextures/glowing ring (filled disc, bright soft rim)
	BandRing = "rbxassetid://15058135927", -- StaticVFXTextures/thick ring 2 (soft medium band)
	NeonRing = "rbxassetid://15268062056", -- StaticVFXTextures/thick ring 3 (crisp inner edge, soft glow)
	CoreSwirl = "rbxassetid://17612139917", -- FlipbookTextures/Whole swirl (Grid4x4): wispy strands circling a core
	Crescent32 = "rbxassetid://17388445727", -- StaticVFXTextures/Crescent32 (layered crescent strokes)
	SoftGlow = "rbxassetid://284205403", -- StaticVFXTextures/Blurred Spec 11
	Bolt = "rbxassetid://137202180073755", -- FlipbookTextures/Lightning Scribble 4x4 (Grid4x4)
	BlackEnergy = "rbxassetid://17511030724", -- FlipbookTextures/Glowing Black Energy (Grid4x4)
	Needle = "rbxassetid://10614304526", -- StaticVFXTextures/Sideways Spec 41
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	CoreArcs = "rbxassetid://73527526679754", -- FlipbookTextures/Blackhole spec (Grid4x4): bright arcs
	CoreShadow = "rbxassetid://107972524433656", -- StaticVFXTextures/Blurry Black Hole
	Flash = "rbxassetid://136210055019402", -- Custom: Starburst (filled spiky shape, white)
	Glint = Textures.Glint, -- drawn: assets/textures/impact.py
	ShockRing = Textures.ShockRing, -- drawn: assets/textures/impact.py
	Wisp = Textures.DustPuff, -- drawn: assets/textures/fire.py (Grid4x4)
}

-- Dark slab and cube templates for the shards (never parented; built per play so
-- overlapping plays with different sizes don't fight). Dark Neon renders flat and unlit.
local function makeShardTemplates(color)
	local templates = {}
	for _ = 1, 2 do
		local part = Layers.Quiet(Instance.new("Part"))
		part.Name = "Shard"
		part.Material = Enum.Material.Neon
		part.Color = color
		table.insert(templates, part)
	end
	return templates
end

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(100, 75, 255), -- violet: dome, haze, light
	AccentColor = Color3.fromRGB(215, 80, 245), -- magenta: band, bolts, lines, the core's rings
	HighlightColor = Color3.fromRGB(235, 210, 255), -- pale lilac: thin hot rings, arcs, the pop
	DeepColor = Color3.fromRGB(45, 15, 160), -- dark violet: disc fill, core rays' dark end
	InkColor = Color3.fromRGB(14, 8, 24), -- near black: shards, jagged streaks, pupil, backdrop
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
	WispRate = 14, -- smoke wisps drawn into the dome per second
	StreakRate = 16, -- streaks skating inward across the ground per second
	ShardCount = 20, -- shards pulled in over Duration
	CaughtShardCount = 5, -- shards already caught in the pull at the start
	ShardSize = 5, -- studs
	ShardPull = 40, -- studs/s^2 inward acceleration of the shards
	LightBrightness = 3,
	LightRange = 24,
	BlackHole = true, -- the anticipation and the held core (false = suction only)
	CoreSize = 2.2, -- studs: the core's radius (R of the orb skeleton)
	CoreSpinSpeed = 600, -- degrees/s of the core's linework and rays
	FlashSize = 11, -- studs: the anticipation star's half-width at its biggest
	FlashTime = 0.42, -- seconds of anticipation before the pull (0 = none)
}

Effect.Linger = 1.1 -- shards (1.05 s) and the core's cross-fading layers (up to 1 s)

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local radius = p.Radius * s

	local ground = Layers.Ground(ctx)
	local anchor = ctx.Anchor(CFrame.new(ground))
	local center = Layers.Attachment(anchor)

	-- 0. Anticipation: a spiky star and its black twin swell while spinning, then implode;
	-- a pop and a ring of bolts as the hole tears open ------------------------------------
	local glint = Layers.Attachment(anchor, CFrame.new(0, 1.2 * s, 0))
	local popLight = Layers.Light(glint, { Color = p.HighlightColor })
	if p.BlackHole and p.FlashTime > 0 then
		local size = p.FlashSize * s
		local star = Layers.Emitter(glint, {
			Texture = ASSETS.Flash,
			Lifetime = p.FlashTime,
			Rotation = 20, -- one angle, shared with the black twin so they line up
			RotSpeed = -720,
			LightEmission = 0,
			Brightness = 4,
			ZOffset = 3,
			Color = { { 0, p.HighlightColor }, { 0.6, p.AccentColor }, { 1, p.Color } },
			-- swells slowly while it spins, then implodes to nothing in the last ~20%
			Size = { { 0, size * 0.15 }, { 0.25, size * 0.8 }, { 0.78, size }, { 1, 0 } },
		})
		-- dark energy: the black twin sits behind and a little bigger, so the star has a
		-- dark rim and reads on bright ground
		Layers.Black(star, -0.1, { Size = { { 0, size * 0.18 }, { 0.25, size * 0.95 }, { 0.78, size * 1.2 }, { 1, 0 } } })
		for _, e in glint:GetChildren() do
			if e:IsA("ParticleEmitter") then
				ctx.Emit(e, 1)
			end
		end
		ctx.Tween(popLight, p.FlashTime, { Brightness = 3, Range = 10 * s }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		ctx.Wait(p.FlashTime)
	end

	-- 1. Implosion pulses ---------------------------------------------------------------
	-- a faint oversized first frame, snaps to full size, then collapses (fast first)
	local function shrink(size)
		return {
			{ 0, size * 1.25 }, { 0.12, size }, { 0.25, size * 0.8 }, { 0.4, size * 0.63 },
			{ 0.55, size * 0.5 }, { 0.7, size * 0.42 }, { 0.85, size * 0.35 }, { 1, size * 0.3 },
		}
	end
	local pulseLife = p.PulseTime
	-- big shells stay faint (a half-transparent dome reads as tinted plastic); the rim and
	-- the band carry the shape
	local dome = Layers.Emitter(center, {
		Texture = ASSETS.GlowDisc,
		Lifetime = pulseLife,
		LightEmission = 0,
		Brightness = 1.5,
		ZOffset = 0.5,
		Color = p.Color,
		Size = shrink(radius * 0.85),
		Transparency = { { 0, 0.95 }, { 0.12, 0.72 }, { 0.6, 0.8 }, { 1, 1 } },
	})
	local domeRim = Layers.Emitter(center, {
		Texture = ASSETS.SphereShell,
		Lifetime = pulseLife,
		LightEmission = 0.3,
		Brightness = 2,
		ZOffset = 0.55,
		Color = p.HighlightColor,
		Size = shrink(radius * 0.87),
		Transparency = { { 0, 0.85 }, { 0.12, 0.2 }, { 0.6, 0.1 }, { 0.9, 0.1 }, { 1, 1 } },
	})
	local disc = Layers.Emitter(center, {
		Flat = true,
		Texture = ASSETS.GlowDisc,
		Lifetime = pulseLife,
		LightEmission = 0,
		Brightness = 1,
		ZOffset = 0.2,
		Color = p.DeepColor,
		Size = shrink(radius * 0.88), -- edge under the band
		Transparency = { { 0, 0.85 }, { 0.12, 0 }, { 0.55, 0.2 }, { 0.85, 1 }, { 1, 1 } },
	})
	-- the ring at the disc's edge: a solid magenta band, then a thin hot ring as it closes
	local band = Layers.Emitter(center, {
		Flat = true,
		Texture = ASSETS.BandRing,
		Lifetime = pulseLife,
		LightEmission = 0.3,
		Brightness = 3,
		ZOffset = 0.7,
		Color = p.AccentColor,
		Size = shrink(radius * 1.04), -- the band's centre line sits at ~0.78 of the quad
		Transparency = { { 0, 0.85 }, { 0.12, 0 }, { 0.5, 0.05 }, { 0.8, 0.6 }, { 1, 1 } },
	})
	local hotRing = Layers.Emitter(center, {
		Flat = true,
		Texture = ASSETS.ShockRing,
		Lifetime = pulseLife,
		LightEmission = 1,
		Brightness = 1.6,
		ZOffset = 0.75,
		Color = p.HighlightColor,
		Size = shrink(radius * 1.06),
		Transparency = { { 0, 1 }, { 0.12, 0.75 }, { 0.35, 0.6 }, { 0.6, 0.2 }, { 0.85, 0 }, { 1, 1 } },
	})

	-- 2. Ground haze, held for the whole pull -------------------------------------------
	local haze = Layers.Emitter(center, {
		Flat = true,
		Texture = ASSETS.SoftGlow,
		Lifetime = p.Duration + 0.3,
		LightEmission = 1,
		Brightness = 0.8,
		Color = p.Color,
		Size = radius * 0.9,
		Transparency = { { 0, 1 }, { 0.1, 0.5 }, { 0.85, 0.55 }, { 1, 1 } },
	})
	local light = Layers.Light(center, { Color = p.Color, Range = math.min(p.LightRange * s, radius * 1.6) })
	local accentLight = Layers.Light(center, { Color = p.AccentColor, Range = radius })

	-- 3. Flickers: lightning, its black jagged twins, thin lines ---------------------------
	local flickerBox = ctx.Anchor(CFrame.new(ground + Vector3.new(0, 4.5 * s, 0)))
	flickerBox.Size = Vector3.new(radius * 2.2, 9 * s, radius * 2.2)
	local function flicker(spec)
		spec.Shape = "Box"
		spec.ShapeStyle = "Volume"
		spec.Orientation = "FacingCameraWorldUp" -- stay vertical
		return Layers.Emitter(flickerBox, spec)
	end
	local bolts = flicker({
		Texture = { Id = ASSETS.Bolt, Grid = 4 },
		EmissionDirection = "Top",
		Speed = { 1 * s, 3 * s },
		Lifetime = { 0.05, 0.09 },
		Rotation = { -8, 8 },
		LightEmission = 0.3, -- solid enough to stay magenta on bright ground
		Brightness = 3,
		ZOffset = 1,
		Color = p.AccentColor,
		Size = { { 0, 3.2 * s, 0.5 * s }, { 1, 3 * s, 0.4 * s } },
		Squash = 0.7, -- tall clusters
		Transparency = { { 0, 0 }, { 0.7, 0.1 }, { 1, 1 } },
	})
	local ink = flicker({
		Texture = { Id = ASSETS.BlackEnergy, Grid = 4 },
		EmissionDirection = "Top",
		Speed = { 1 * s, 3 * s },
		Lifetime = { 0.06, 0.11 },
		Rotation = { -4, 4 },
		LightEmission = 0,
		ZOffset = 0.9,
		Color = p.InkColor,
		Size = { { 0, 2.3 * s, 0.3 * s }, { 1, 2.1 * s, 0.3 * s } },
		Squash = 1.4,
		Transparency = { { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } },
	})
	local function line(color, size, zOffset, brightness)
		return flicker({
			Texture = ASSETS.Needle,
			EmissionDirection = "Bottom",
			Speed = { 4 * s, 8 * s },
			Lifetime = { 0.1, 0.18 },
			LightEmission = 0,
			Brightness = brightness,
			ZOffset = zOffset,
			Color = color,
			Size = { { 0, size * s, 0.4 * s }, { 1, (size - 0.2) * s, 0.4 * s } },
			Squash = 0.6,
			Transparency = { { 0, 0.05 }, { 0.7, 0.1 }, { 1, 1 } },
		})
	end
	local glowLines = line(p.AccentColor, 3.6, 1, 2)
	local inkLines = line(Layers.BLACK, 3.4, 0.9, 1)

	-- 4. Specks, wisps and floor streaks pulled inward ------------------------------------
	local speckShell = ctx.Anchor(CFrame.new(ground))
	speckShell.Size = Vector3.one * radius * 2.2
	local speckTime = p.SpeckTime
	local speckSpeed = radius * 1.1 / speckTime
	local function inward(spec)
		spec.Shape = "Sphere"
		spec.ShapeStyle = "Surface"
		spec.ShapeInOut = "Inward"
		spec.ShapePartial = 0.5 -- upper half only
		return Layers.Emitter(speckShell, spec)
	end
	local function speckEmitter(color, zOffset)
		return inward({
			Speed = speckSpeed,
			Lifetime = { speckTime * 0.7, speckTime * 0.95 }, -- gone before the centre
			Texture = ASSETS.Speck,
			Rotation = { 0, 360 },
			RotSpeed = { -300, 300 },
			LightEmission = 0,
			Brightness = 2,
			ZOffset = zOffset,
			Color = color,
			Size = { { 0, 0 }, { 0.2, 0.18 * s, 0.05 * s }, { 0.8, 0.15 * s }, { 1, 0 } },
		})
	end
	local accentSpecks = speckEmitter(p.AccentColor, 1)
	local darkSpecks = speckEmitter(p.InkColor, 0.8)
	local wisps = inward({
		Speed = speckSpeed * 0.8,
		Lifetime = { speckTime * 0.8, speckTime * 1.1 },
		Texture = ASSETS.Wisp,
		Rotation = { 0, 360 },
		RotSpeed = { -120, 120 },
		LightEmission = 0,
		Brightness = 1.5,
		ZOffset = 0.65,
		Color = p.HighlightColor:Lerp(p.Color, 0.4), -- smoke beside the energy takes its tint
		Size = { { 0, 2.5 * s, 0.5 * s }, { 1, 0.4 * s } },
		Transparency = { { 0, 1 }, { 0.25, 0.6 }, { 0.75, 0.7 }, { 1, 1 } },
	})
	local floorRing = ctx.Anchor(CFrame.new(ground + Vector3.new(0, 0.15 * s, 0)))
	-- a Sphere shape on a flattened part is an ellipse on the floor; Inward then sends
	-- particles radially to the centre (Disc/Cylinder shapes don't; structure.md)
	floorRing.Size = Vector3.new(radius * 2.4, 0.2, radius * 2.4)
	local floorStreaks = Layers.Emitter(floorRing, {
		Shape = "Sphere",
		ShapeStyle = "Surface",
		ShapeInOut = "Inward",
		Speed = speckSpeed,
		Lifetime = { speckTime * 0.6, speckTime * 0.85 },
		Orientation = "VelocityParallel",
		Texture = ASSETS.SoftGlow,
		LightEmission = 1,
		Brightness = 1.5,
		ZOffset = 0.3,
		Color = p.HighlightColor,
		Size = { { 0, 0 }, { 0.2, 0.6 * s }, { 1, 0.3 * s } },
		Squash = 3,
		Transparency = { { 0, 0.5 }, { 0.7, 0.6 }, { 1, 1 } },
	})

	-- 5. Shards: dark slabs and cubes pulled into the centre ------------------------------
	local templates = makeShardTemplates(p.InkColor)
	local shardSize = p.ShardSize * s
	templates[1].Size = Vector3.new(shardSize, shardSize * 0.22, shardSize * 0.6) -- slab
	templates[2].Size = Vector3.one * shardSize * 0.3 -- cube
	local pullPoint = ground + Vector3.new(0, 1.5 * s, 0)
	local shardIndex = 0
	local shardFade = Layers.Seq({ { 0, 1 }, { 0.1, 0.7 }, { 0.6, 0.45 }, { 0.9, 0.3 }, { 1, 1 } })
	local shardGrow = Layers.Seq({ { 0, 0.5 }, { 0.1, 1 }, { 0.6, 0.9 }, { 1, 0 } })
	local caughtFade = Layers.Seq({ { 0, 0.6 }, { 0.6, 0.45 }, { 0.9, 0.3 }, { 1, 1 } })
	local caughtGrow = Layers.Seq({ { 0, 1 }, { 0.6, 0.9 }, { 1, 0 } })
	local function spawnShard(caught)
		shardIndex += 1
		local angle = math.random() * math.pi * 2
		local r = radius * (0.9 + math.random() * 0.5)
		local height = 2.5 + math.random() * (if caught then 6 else 9) -- off the floor
		local origin = ground + Vector3.new(math.cos(angle) * r, height * s, math.sin(angle) * r)
		local toCentre = (pullPoint - origin).Unit
		MeshParticles.Burst(ctx, templates[if shardIndex % 3 == 0 then 2 else 1], 1, {
			Origin = origin,
			Direction = toCentre,
			Spread = 20,
			Speed = NumberRange.new(1 * s, 3 * s),
			Acceleration = toCentre * p.ShardPull * s,
			SpinSpeed = NumberRange.new(40, 160),
			Scale = 0.6 + math.random() * 0.6,
			Lifetime = NumberRange.new(0.9, 1.05), -- consumed just before reaching the centre
			Size = if caught then caughtGrow else shardGrow,
			Transparency = if caught then caughtFade else shardFade,
		})
	end

	-- 6. Black hole core: an orb (front to back), every layer cross-fading ----------------
	local coreLayers, coreArcs, coreBall = {}, nil, nil
	if p.BlackHole then
		local R = p.CoreSize * s
		-- raised so the ground cuts only its bottom
		local orbAtt = Layers.Attachment(anchor, CFrame.new(0, R * 0.5, 0))
		local function held(spec)
			spec.LockedToPart = true
			spec.Rate = 3
			spec.Lifetime = spec.Lifetime or { 0.6, 0.9 }
			spec.Transparency = spec.Transparency or { { 0, 1 }, { 0.5, 0 }, { 1, 1 } }
			spec.Enabled = false
			local e = Layers.Emitter(orbAtt, spec)
			table.insert(coreLayers, e)
			return e
		end
		local zFront = R -- in front of the pupil ball's near side
		held({ -- black linework spinning over everything
			Texture = ASSETS.Crescent32,
			Rotation = { 0, 360 },
			RotSpeed = p.CoreSpinSpeed,
			LightEmission = 0,
			ZOffset = zFront + 0.4,
			Color = Layers.BLACK,
			Size = 1.1 * R,
		})
		held({ -- hard ring
			Texture = ASSETS.NeonRing,
			LightEmission = 0,
			Brightness = 8,
			ZOffset = zFront + 0.3,
			Color = p.AccentColor,
			Size = 1.2 * R, -- the ring sits at ~0.75 of the quad: ~0.9 R
		})
		held({ -- swirling rays round the pupil
			Texture = { Id = ASSETS.CoreSwirl, Grid = 4 },
			FlipbookMode = "Loop",
			FlipbookFramerate = 20,
			Rotation = { 0, 360 },
			RotSpeed = -p.CoreSpinSpeed * 0.6,
			LightEmission = 1,
			Brightness = 5,
			ZOffset = zFront,
			Color = { { 0, p.HighlightColor }, { 1, p.DeepColor } },
			Size = 1.3 * R,
			Transparency = { { 0, 1 }, { 0.5, 0.3 }, { 1, 1 } },
		})
		held({ -- outer ring, growing
			Texture = ASSETS.ShockRing,
			LightEmission = 1,
			Brightness = 2,
			ZOffset = -1,
			Color = p.AccentColor,
			Size = { { 0, 1.2 * R }, { 1, 2 * R } },
			Rotation = { 0, 360 },
		})
		held({ -- soft halo
			Texture = ASSETS.SoftGlow,
			LightEmission = 1,
			Brightness = 0.3,
			ZOffset = -1.05,
			Color = p.Color,
			Size = 1.6 * R,
		})
		held({ -- black backdrop
			Texture = ASSETS.CoreShadow,
			LightEmission = 0,
			ZOffset = -1.1,
			Color = Layers.BLACK,
			Size = 2 * R,
			Transparency = { { 0, 1 }, { 0.5, 0.1 }, { 1, 1 } },
		})
		-- the black pupil: a solid dark ball (dark Neon renders flat and unlit)
		coreBall = Layers.Part(ctx, {
			Name = "Core",
			Shape = Enum.PartType.Ball,
			Material = "Neon",
			Color = p.InkColor,
			Size = Vector3.one * 0.1,
			CFrame = anchor.CFrame * CFrame.new(0, R * 0.5, 0),
		})
		-- arcs flashing with each pulse
		coreArcs = Layers.Emitter(orbAtt, {
			Texture = { Id = ASSETS.CoreArcs, Grid = 4 },
			Lifetime = p.PulseInterval * 1.2,
			Rotation = { -70, 70 },
			LightEmission = 1,
			Brightness = 1.5,
			ZOffset = zFront + 0.2,
			Color = p.HighlightColor,
			Size = { { 0, R * 1.25, R * 0.15 }, { 1, R * 1.1, R * 0.1 } },
			Transparency = { { 0, 0 }, { 0.7, 0.15 }, { 1, 1 } },
		})
	end
	-- the pop as the hole opens: a small white-hot flash over a flare line
	local pop = Layers.Emitter(glint, {
		Texture = ASSETS.Flash,
		Lifetime = 0.07,
		Rotation = { 0, 360 },
		LightEmission = 0,
		Brightness = 8,
		ZOffset = 3.2,
		Color = { { 0, Layers.WHITE }, { 1, p.HighlightColor } },
		Size = { { 0, 0.5 * s }, { 0.35, 4 * s }, { 1, 4.5 * s } },
		Transparency = { { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } },
	})
	local popFlare = Layers.Emitter(glint, {
		Texture = ASSETS.Glint,
		Lifetime = 0.06,
		LightEmission = 1,
		Brightness = 6,
		ZOffset = 3.3,
		Color = p.HighlightColor,
		Size = { { 0, 6 * s }, { 1, 8 * s } },
		Squash = -3,
		Transparency = { { 0, 0 }, { 1, 1 } },
	})

	-- 7. Timeline -----------------------------------------------------------------------
	local rates = {
		{ bolts, p.BoltRate },
		{ ink, p.InkRate },
		{ glowLines, p.LineRate / 2 },
		{ inkLines, p.LineRate / 2 },
		{ accentSpecks, p.SpeckRate * 0.6 },
		{ darkSpecks, p.SpeckRate * 0.4 },
		{ wisps, p.WispRate },
		{ floorStreaks, p.StreakRate },
	}
	ctx.Emit(haze, 1)
	if p.BlackHole then -- the hole tears open with a pop and a ring of bolts and black streaks
		ctx.Emit(pop, 1)
		ctx.Emit(popFlare, 1)
		Layers.Pop(ctx, popLight, 6, 6 * s, 18 * s, 0.25)
		ctx.Emit(bolts, 8)
		ctx.Emit(ink, 3)
		for _, e in coreLayers do
			e.TimeScale = ctx.TimeScale
			e.Enabled = true
			ctx.Emit(e, 1) -- shows from the first frame; the Rate keeps it held
		end
		ctx.Tween(coreBall, 0.07, { Size = Vector3.one * p.CoreSize * s * 1.35 })
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
			ctx.Emit(dome, 1)
			ctx.Emit(domeRim, 1)
			ctx.Emit(disc, 2)
			ctx.Emit(band, 1)
			ctx.Emit(hotRing, 1)
			if coreArcs then
				ctx.Emit(coreArcs, 2) -- two random tilts so the arcs cross
			end
			light.Brightness = p.LightBrightness * 1.5
			ctx.Tween(light, p.PulseInterval, { Brightness = p.LightBrightness * 0.4 })
			accentLight.Brightness = p.LightBrightness
			ctx.Tween(accentLight, p.PulseInterval * 0.7, { Brightness = 0 })
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
		-- ctx.Wait returns the effect time that really passed (a 1/60 wait often takes two
		-- frames); counting 1/60 per loop would stretch every interval
		dt = ctx.Wait(1 / 60)
		elapsed += dt
	end
	for _, e in coreLayers do
		e.Enabled = false -- the held core cross-fades out over its last lifetimes
	end
	ctx.Tween(light, 0.3, { Brightness = 0 })
	if coreBall then
		ctx.Tween(coreBall, 0.2, { Size = Vector3.one * 0.1, Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
end

return Effect
