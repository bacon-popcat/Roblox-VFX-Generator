-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/WindSpinSlash
-- Green wind spin-slash around the caster. Layers: steeply tilted vortex of
-- spinning crescent strokes (dark green body, lime/white highlights, thin black
-- ink strokes woven through), black needle streaks and white-hot spots shed along
-- the spinning arc, a star flash that grows then snaps shut, a grey wind ring +
-- smoke on the ground, rising thin crescents, leaves, sparkles and rock debris.
--
-- ctx.CFrame: the caster's root. The vortex is centred on the ground below it.
-- It tilts toward SwirlTiltYaw (degrees from the caster's facing): that side
-- dips to the ground and the opposite side rises.
--
-- Every vortex layer is one flat particle (Orientation VelocityPerpendicular,
-- tiny upward speed) so it lies in the tilted plane and spins with RotSpeed.
-- ParticleEmitter.Size is a half-width: Size = r draws a 2r x 2r quad.
-- Scattered layers (smoke, sparkles, spots) emit from invisible Disc-shaped
-- parts: moving an Attachment between Emit calls in one frame does not move
-- the spawn point, so every burst would land in the same spot.

local VFX = script.Parent.Parent
local MeshParticles = require(VFX:WaitForChild("MeshParticles"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	WideDarkSlash = "rbxassetid://104673447334638", -- FlipbookTextures/Wide Dark Slash (Grid4x4)
	GlowingDarkSlash = "rbxassetid://107491452097107", -- FlipbookTextures/Medium Glowing Dark Slash (Grid4x4)
	GlowingSlash = "rbxassetid://13580352351", -- FlipbookTextures/Glowing Slash (Grid4x4)
	ThinSlash = "rbxassetid://85263893313331", -- FlipbookTextures/Thin Basic Slash (Grid4x4)
	StreakySlash = "rbxassetid://118897571793559", -- FlipbookTextures/Shaded Slash 5 (Grid4x4)
	Needle = "rbxassetid://10614304526", -- StaticVFXTextures/Sideways Spec 41
	Spike = "rbxassetid://6893847210", -- StaticVFXTextures/Sideways Spec 50
	Crescent32 = "rbxassetid://17388445727", -- StaticVFXTextures/Crescent32
	Crescent18 = "rbxassetid://17388365742", -- StaticVFXTextures/Crescent18
	SmokeyShockwave = "rbxassetid://12318427672", -- StaticVFXTextures/Smokey Shockwave
	Swirls21 = "rbxassetid://130391463304711", -- StaticVFXTextures/Swirls21
	StarRays = "rbxassetid://17391818367", -- StaticVFXTextures/Star102
	SoftGlow = "rbxassetid://284205403", -- StaticVFXTextures/Blurred Spec 11
	Sparkle = "rbxassetid://16444981264", -- StaticVFXTextures/Star153
	Smoke = "rbxassetid://111394301752764", -- StaticVFXTextures/smoke 41
	Debris = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	LeafMesh = "rbxassetid://5129539702", -- MigratedMeshes/Leaf (native 5.45 x 1.61 x 11.0)
}

local LEAF_MESH_LENGTH = 11 -- native Z length of LeafMesh, for scaling

-- Vortex layers, one flat spinning crescent particle each.
--   size  fraction of SwirlRadius            h     height offset (fraction of radius)
--   tilt  extra tilt (deg)                   spin  multiplier on SpinSpeed
--   rot   start angle offset (deg). Each texture's arc sits at a different angle in
--         its quad, so these phase the arcs into one ~180 deg crescent (an open C)
--   life  multiplier on SwirlTime            flip  4x4 flipbook played once
--   kind  "dark" (darkens), "lime" (additive), "hot" (additive, near white),
--         "ink" (near-black thin strokes drawn over the lime)
--   alpha starting transparency for "ink" layers (default 0.05)
local VORTEX = {
	{ tex = "WideDarkSlash", flip = true, kind = "dark", size = 0.9, h = 0.0, tilt = 0, spin = 0.97, rot = -35, life = 1.05 },
	{ tex = "WideDarkSlash", flip = true, kind = "dark", size = 0.82, h = 0.12, tilt = 4, spin = 1.0, rot = -25, life = 1.05 },
	{ tex = "GlowingDarkSlash", flip = true, kind = "lime", size = 1.1, h = -0.05, tilt = -3, spin = 0.98, rot = 5, life = 1 },
	{ tex = "GlowingDarkSlash", flip = true, kind = "lime", size = 1.0, h = 0.18, tilt = 6, spin = 1.03, rot = 15, life = 1 },
	{ tex = "Crescent32", kind = "lime", size = 1.05, h = 0.08, tilt = 2, spin = 1.0, rot = 10, life = 0.9 },
	{ tex = "GlowingSlash", flip = true, kind = "hot", size = 0.98, h = 0.08, tilt = 2, spin = 1.02, rot = -45, life = 0.8 },
	{ tex = "ThinSlash", flip = true, kind = "ink", size = 1.04, h = 0.05, tilt = 2, spin = 1.0, rot = 15, life = 0.9 },
	{ tex = "ThinSlash", flip = true, kind = "ink", size = 0.9, h = 0.12, tilt = 4, spin = 1.04, rot = 35, life = 0.85 },
	{ tex = "StreakySlash", flip = true, kind = "ink", size = 1.08, h = 0.0, tilt = 0, spin = 0.99, rot = 25, life = 0.95, alpha = 0.4 },
}

-- Which way the shed streaks orbit (+1/-1) so they travel with the spinning
-- arcs; ParticleEmitter RotSpeed and the orbit angle turn opposite ways
local ORBIT_SIGN = -1

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

-- Props shared by every flat, ground-aligned particle layer
local function flat(props)
	props.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	props.EmissionDirection = Enum.NormalId.Top
	props.SpreadAngle = props.SpreadAngle or Vector2.zero
	props.Speed = props.Speed or NumberRange.new(0.01)
	return props
end

-- Ground point under the caster, skipping characters and non-collidable parts
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

local leafTemplate
local function getLeafTemplate()
	if not leafTemplate then
		local part = Instance.new("Part")
		part.Name = "Leaf"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Size = Vector3.one * 0.2
		part.Material = Enum.Material.SmoothPlastic
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = ASSETS.LeafMesh
		mesh.Parent = part
		leafTemplate = part
	end
	return leafTemplate
end

--------------------------------------------------------------------------------

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(70, 235, 30), -- saturated lime
	CoreColor = Color3.fromRGB(230, 255, 200), -- near-white highlight
	DarkColor = Color3.fromRGB(18, 90, 28), -- dark green body
	InkColor = Color3.fromRGB(6, 20, 9), -- thin black strokes and streaks
	WindColor = Color3.fromRGB(205, 212, 222), -- grey wind ring + smoke
	LeafColor = Color3.fromRGB(50, 140, 45),
	Scale = 1,
	SwirlRadius = 12, -- studs
	SwirlHeight = 4.5, -- studs above the ground (vortex centre)
	SwirlTilt = 22, -- degrees
	SwirlTiltYaw = -45, -- degrees from the caster's facing; that side dips
	SwirlStartAngle = 90, -- degrees; where the lopsided arc starts
	SpinSpeed = 900, -- degrees/sec
	SpinDirection = 1, -- 1 or -1
	SwirlTime = 0.27, -- life of the thick vortex
	FlashSize = 14, -- glare half-width, studs
	FlashTime = 0.07, -- glint, grows (25%), holds, then shrinks to nothing in the last 30%
	StreakTime = 0.22, -- seconds black streaks and hot spots are shed along the arc
	StreakCount = 3, -- black streaks shed per frame while StreakTime runs
	RingSize = 26, -- half-width of the ground wind-ring texture, studs
	LeafCount = 3,
	LeafRiseCount = 2, -- upright leaves rising slowly inside the vortex
	SparkleCount = 18,
	SpotCount = 8,
	SmokeCount = 18,
	DebrisCount = 10,
	DebrisColor = Color3.fromRGB(52, 42, 34), -- dark brown rock chips
	LightBrightness = 1.5,
}

Effect.Linger = 1.6

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local radius = p.SwirlRadius * s
	local spin = p.SpinSpeed * p.SpinDirection

	local ground = findGround(ctx)
	local look = ctx.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local anchor = ctx.Anchor(CFrame.new(ground) * CFrame.Angles(0, yaw, 0))

	local function attachment(cf)
		local a = Instance.new("Attachment")
		a.CFrame = cf
		a.Parent = anchor
		return a
	end

	local swirlCenter = CFrame.new(0, p.SwirlHeight * s, 0)
	local function tilted(extraHeight, extraTilt)
		return swirlCenter
			* CFrame.new(0, extraHeight, 0)
			* CFrame.Angles(0, math.rad(p.SwirlTiltYaw), 0)
			* CFrame.Angles(-math.rad(p.SwirlTilt + extraTilt), 0, 0)
	end

	-- 1. Vortex body ----------------------------------------------------------
	local startAngle = p.SwirlStartAngle + math.random(-20, 20)
	local layerAttachments = {} -- layers with the same height and tilt share one
	for _, layer in VORTEX do
		local key = layer.h .. ":" .. layer.tilt
		layerAttachments[key] = layerAttachments[key] or attachment(tilted(layer.h * radius, layer.tilt))
		local kind = layer.kind
		local isMatter = kind == "dark" or kind == "ink"
		local size = radius * layer.size
		local e = emitter(layerAttachments[key], flat({
			Texture = ASSETS[layer.tex],
			Speed = NumberRange.new(8 * s), -- drifts ~2.5 studs along its normal
			Drag = 3,
			Lifetime = NumberRange.new(p.SwirlTime * layer.life),
			Rotation = NumberRange.new(startAngle + layer.rot),
			RotSpeed = NumberRange.new(spin * layer.spin),
			-- Additive lime stays saturated only over the dark layers behind it;
			-- partial LightEmission turns the textures' dark pixels black
			LightEmission = isMatter and 0 or 1,
			Brightness = kind == "hot" and 1.5 or 1,
			ZOffset = if kind == "dark" then -1 elseif kind == "ink" then 1.5 elseif kind == "hot" then 2 else 1,
			Size = seq({ { 0, size * 0.92 }, { 0.25, size }, { 1, size * 1.1 } }),
			Transparency = if kind == "dark"
				then seq({ { 0, 0.15 }, { 0.6, 0.25 }, { 1, 1 } })
				elseif kind == "ink" then seq({ { 0, layer.alpha or 0.05 }, { 0.55, (layer.alpha or 0.05) + 0.15 }, { 1, 1 } })
				else seq({ { 0, 0 }, { 0.6, 0.05 }, { 1, 1 } }),
			Color = if kind == "dark"
				then ColorSequence.new(p.DarkColor)
				elseif kind == "ink" then ColorSequence.new(p.InkColor)
				elseif kind == "hot" then colors({ { 0, p.CoreColor }, { 0.5, p.CoreColor:Lerp(p.Color, 0.4) }, { 1, p.Color } })
				else ColorSequence.new(p.Color),
			FlipbookLayout = layer.flip and Enum.ParticleFlipbookLayout.Grid4x4 or Enum.ParticleFlipbookLayout.None,
			FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		}))
		ctx.Emit(e, 1)
	end

	-- 2. Light pop --------------------------------------------------------------
	local groundAttachment = attachment(CFrame.new(0, 0.2 * s, 0))
	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = math.min(20, 10 * s)
	light.Brightness = p.LightBrightness
	light.Parent = groundAttachment
	ctx.Tween(light, 0.12, { Brightness = 0 })

	-- 2b. Black streaks and white-hot spots shed along the spinning arc -----------
	-- One attachment orbits the vortex at its spin rate, shedding thin black
	-- spikes along the arc's direction of travel, lime needles and hot spots.
	local orbitCenter = tilted(0.08 * radius, 2)
	local orbit = attachment(orbitCenter)
	local inkStreaks = emitter(orbit, {
		Texture = ASSETS.Spike,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Rotation = NumberRange.new(90), -- texture is vertical; lay it along the motion
		EmissionDirection = p.SpinDirection > 0 and Enum.NormalId.Front or Enum.NormalId.Back,
		SpreadAngle = Vector2.new(12, 12),
		Speed = NumberRange.new(6 * s, 14 * s),
		Drag = 8,
		Lifetime = NumberRange.new(0.12, 0.22),
		LightEmission = 0,
		ZOffset = 2,
		Color = ColorSequence.new(p.InkColor),
		Size = seq({ { 0, 1.6 * s, 0.4 * s }, { 0.6, 1.2 * s }, { 1, 0 } }),
		Squash = NumberSequence.new(0.4), -- short wedges, not long hairs
		Transparency = seq({ { 0, 0.05 }, { 0.7, 0.2 }, { 1, 1 } }),
	})
	local limeStreaks = emitter(orbit, {
		Texture = ASSETS.Needle,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Rotation = NumberRange.new(90),
		EmissionDirection = p.SpinDirection > 0 and Enum.NormalId.Front or Enum.NormalId.Back,
		SpreadAngle = Vector2.new(15, 15),
		Speed = NumberRange.new(25 * s, 40 * s),
		Drag = 6,
		Lifetime = NumberRange.new(0.1, 0.18),
		LightEmission = 1,
		Brightness = 2,
		ZOffset = 2,
		Color = colors({ { 0, p.CoreColor }, { 1, p.Color } }),
		Size = seq({ { 0, 1.4 * s }, { 1, 0 } }),
	})
	local hotSpots = emitter(orbit, {
		Texture = ASSETS.SoftGlow,
		Lifetime = NumberRange.new(0.04, 0.07),
		LightEmission = 1,
		Brightness = 3,
		ZOffset = 2.2,
		Color = colors({ { 0, p.CoreColor }, { 1, p.Color } }),
		Size = seq({ { 0, 1.1 * s }, { 1, 0.3 * s } }),
		Transparency = seq({ { 0, 0.1 }, { 1, 1 } }),
	})
	task.spawn(function()
		local spinRadians = math.rad(p.SpinSpeed) * ORBIT_SIGN * p.SpinDirection
		local angle = math.rad(startAngle)
		local elapsed, step = 0, 0
		while elapsed < p.StreakTime and ctx.Folder.Parent do
			step += 1
			local r = radius * (0.7 + math.random() * 0.25)
			orbit.CFrame = orbitCenter
				* CFrame.Angles(0, angle + spinRadians * elapsed + (math.random() - 0.5) * 0.6, 0)
				* CFrame.new(r, (math.random() - 0.5) * 1.2 * s, 0)
			ctx.Emit(inkStreaks, p.StreakCount)
			if step % 2 == 0 then
				ctx.Emit(limeStreaks, 1)
			end
			if step % 3 == 1 and elapsed < 0.1 then
				ctx.Emit(hotSpots, 1)
			end
			ctx.Wait(1 / 60)
			elapsed += 1 / 60
		end
	end)

	ctx.Wait(0.01)

	-- 3. Star flash: glint at 0.01s, full by ~0.03s, holds, then shrinks fast ----
	local flashAttachment = attachment(CFrame.new(0, 6 * s, 0)) -- high enough that the glow clears the ground
	local flashSize = p.FlashSize * s
	-- Size over the flash's life: small glint, full size, hold, shrink to nothing.
	-- `jitter` is the keypoint envelope (random size variation per flash).
	local function flashCurve(scale, jitter)
		jitter = jitter or 0
		return seq({
			{ 0, flashSize * scale * 0.08, jitter * 0.2 },
			{ 0.25, flashSize * scale, jitter },
			{ 0.7, flashSize * scale * 0.97, jitter },
			{ 1, 0 },
		})
	end
	local flashFade = seq({ { 0, 0 }, { 0.8, 0 }, { 1, 0.4 } })
	local rays = emitter(flashAttachment, {
		Texture = ASSETS.StarRays,
		Lifetime = NumberRange.new(p.FlashTime),
		-- Star102 is an even X of rays; at about -15 it sits as a "+" (vertical and
		-- horizontal rays), like the reference. + turns counter-clockwise.
		Rotation = NumberRange.new(-20, -10),
		LightEmission = 1,
		Brightness = 5,
		ZOffset = 3,
		Color = colors({ { 0, Color3.new(1, 1, 1) }, { 1, p.Color } }),
		Size = flashCurve(1, flashSize * 0.2),
		Transparency = flashFade,
	})
	local longRay = emitter(flashAttachment, {
		Texture = ASSETS.Needle,
		Lifetime = NumberRange.new(p.FlashTime),
		Rotation = NumberRange.new(-48, -40), -- the long thin ray up and to the right
		LightEmission = 1,
		Brightness = 4,
		ZOffset = 3,
		Color = colors({ { 0, p.CoreColor }, { 1, p.Color:Lerp(p.CoreColor, 0.3) } }),
		Size = flashCurve(1.35),
		Squash = NumberSequence.new(1.6), -- a hair-thin, long line
		Transparency = flashFade,
	})
	local glow = emitter(flashAttachment, {
		Texture = ASSETS.SoftGlow,
		Lifetime = NumberRange.new(p.FlashTime),
		LightEmission = 1,
		Brightness = 3.5,
		ZOffset = 2.5,
		Color = colors({ { 0, p.CoreColor }, { 1, p.Color } }),
		Size = flashCurve(0.38),
		Transparency = flashFade,
	})
	ctx.Emit(rays, 1)
	ctx.Emit(longRay, 1)
	ctx.Emit(glow, 1)

	ctx.Wait(0.015)

	-- 4. Ground wind ring + smoke ----------------------------------------------
	local ringSize = p.RingSize * s
	local ring = emitter(groundAttachment, flat({
		Texture = ASSETS.SmokeyShockwave,
		Lifetime = NumberRange.new(0.6),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(spin * 0.15),
		LightEmission = 0,
		Color = ColorSequence.new(p.WindColor),
		Size = seq({ { 0, ringSize * 0.75 }, { 1, ringSize * 1.35 } }),
		Transparency = seq({ { 0, 0.7 }, { 0.12, 0.5 }, { 0.4, 0.75 }, { 1, 1 } }),
	}))
	local ringLines = emitter(groundAttachment, flat({
		Texture = ASSETS.Swirls21,
		Lifetime = NumberRange.new(0.6),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(spin * 0.3),
		LightEmission = 0,
		Color = ColorSequence.new(p.WindColor),
		Size = seq({ { 0, ringSize * 0.65 }, { 1, ringSize * 1.0 } }),
		Transparency = seq({ { 0, 0.6 }, { 0.15, 0.4 }, { 0.6, 0.65 }, { 1, 1 } }),
	}))
	ctx.Emit(ring, 1)
	ctx.Emit(ringLines, 1)

	-- Invisible disc parts that scatter particles over an area (see header)
	local function scatterPart(discRadius, height)
		local part = ctx.Anchor(anchor.CFrame * CFrame.new(0, height, 0))
		part.Size = Vector3.new(discRadius * 2, 0.1, discRadius * 2)
		return part
	end
	local smokeRing = scatterPart(radius * 1.5, 0.4 * s)
	local smoke = emitter(smokeRing, flat({
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapePartial = 0.8, -- mostly fills the disc, thinning toward the centre
		Texture = ASSETS.Smoke,
		Lifetime = NumberRange.new(0.9, 1.4),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		LightEmission = 0,
		LightInfluence = 0.5,
		Color = ColorSequence.new(p.WindColor),
		Size = seq({ { 0, 4 * s }, { 1, 10 * s } }),
		Transparency = seq({ { 0, 1 }, { 0.15, 0.78 }, { 1, 1 } }),
	}))
	ctx.Emit(smoke, p.SmokeCount)

	-- 5. Leaves, sparkles, rising thin crescents --------------------------------
	local leaf = getLeafTemplate()
	leaf.Color = p.LeafColor
	leaf.Mesh.Scale = Vector3.one * (4.5 * s / LEAF_MESH_LENGTH)
	-- One burst per leaf: Burst only sprays a cone around a single direction
	local leafAngle = math.random() * math.pi * 2
	for i = 1, p.LeafCount do
		-- evenly spaced around the caster, with jitter, so leaves never clump on one side
		local angle = leafAngle + (i / p.LeafCount) * math.pi * 2 + (math.random() - 0.5)
		MeshParticles.Burst(ctx, leaf, 1, {
			Origin = ground + Vector3.new(0, 1.2 * s, 0),
			Direction = Vector3.new(math.cos(angle), 0.15, math.sin(angle)),
			Spread = 15,
			Speed = NumberRange.new(55 * s, 62 * s),
			Drag = 2.5,
			Acceleration = Vector3.new(0, -12, 0),
			SpinSpeed = NumberRange.new(60, 160),
			Lifetime = NumberRange.new(1.1, 1.25),
			Transparency = seq({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }),
		})
	end
	-- A couple of upright leaves lifted slowly inside the vortex
	if p.LeafRiseCount > 0 then
		MeshParticles.Burst(ctx, leaf, p.LeafRiseCount, {
			Origin = ground + Vector3.new(0, 1 * s, 0),
			SpawnRadius = radius * 0.45,
			Direction = Vector3.yAxis,
			Spread = 20,
			Speed = NumberRange.new(3 * s, 5 * s),
			Drag = 2,
			Acceleration = Vector3.new(0, -6, 0),
			SpinSpeed = NumberRange.new(120, 240),
			Lifetime = NumberRange.new(0.7, 0.9),
			Transparency = seq({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }),
		})
	end

	ctx.Wait(0.03)

	local area = scatterPart(radius * 0.95, 0.5 * s)
	local sparkles = emitter(area, {
		Shape = Enum.ParticleEmitterShape.Disc,
		EmissionDirection = Enum.NormalId.Top,
		Texture = ASSETS.Sparkle,
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(2 * s, 10 * s),
		SpreadAngle = Vector2.new(30, 30),
		Drag = 3,
		Acceleration = Vector3.new(0, 2, 0),
		LightEmission = 1,
		Brightness = 3,
		ZOffset = 2,
		Color = colors({ { 0, p.Color:Lerp(p.CoreColor, 0.3) }, { 1, p.Color } }),
		Size = seq({ { 0, 0 }, { 0.1, 0.5 * s }, { 0.5, 0.3 * s }, { 0.7, 0.45 * s }, { 1, 0 } }),
		Transparency = seq({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } }),
	})
	ctx.Emit(sparkles, p.SparkleCount)

	local lines = emitter(attachment(tilted(radius * 0.2, 4)), flat({
		Texture = ASSETS.Crescent18,
		SpreadAngle = Vector2.new(4, 4),
		Speed = NumberRange.new(8 * s, 12 * s),
		Drag = 4,
		Lifetime = NumberRange.new(0.18, 0.22),
		Rotation = NumberRange.new(startAngle, startAngle + 20),
		RotSpeed = NumberRange.new(spin * 0.9),
		LightEmission = 0.4, -- clean texture, so partial additive keeps it saturated
		Brightness = 1,
		ZOffset = 1.5,
		Color = colors({ { 0, p.Color:Lerp(p.CoreColor, 0.3) }, { 0.3, p.Color }, { 1, p.Color } }),
		Size = seq({ { 0, radius }, { 1, radius * 1.15 } }),
		Transparency = seq({ { 0, 1 }, { 0.1, 0 }, { 0.5, 0.1 }, { 1, 1 } }),
	}))
	ctx.Emit(lines, 2)

	-- Green glow spots left on the ground inside the ring
	local spots = emitter(area, flat({
		Shape = Enum.ParticleEmitterShape.Disc,
		Texture = ASSETS.SoftGlow,
		Lifetime = NumberRange.new(0.3, 0.45),
		LightEmission = 1,
		Color = ColorSequence.new(p.Color),
		Size = seq({ { 0, 1.3 * s, 0.4 * s }, { 1, 1 * s } }),
		Transparency = seq({ { 0, 0.3 }, { 1, 1 } }),
	}))
	ctx.Emit(spots, p.SpotCount)

	ctx.Wait(0.06)

	-- 6. Dark debris -------------------------------------------------------------
	local debris = emitter(groundAttachment, {
		Texture = ASSETS.Debris,
		Lifetime = NumberRange.new(0.5, 0.8),
		Speed = NumberRange.new(18 * s, 28 * s),
		SpreadAngle = Vector2.new(60, 60),
		Drag = 2,
		Acceleration = Vector3.new(0, -60, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-360, 360),
		LightEmission = 0,
		LightInfluence = 0.4,
		Color = ColorSequence.new(p.DebrisColor),
		Size = seq({ { 0, 0.35 * s, 0.15 * s }, { 1, 0.15 * s } }),
		Transparency = seq({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }),
	})
	ctx.Emit(debris, p.DebrisCount)

	ctx.Wait(p.SwirlTime)
end

return Effect
