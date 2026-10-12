-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/WindSpinSlash
-- Green wind spin-slash around the caster. Layers: steeply tilted vortex of
-- spinning crescent strokes (dark green body + lime/white highlights), a short
-- star flash, a grey wind ring + smoke on the ground, rising thin crescents,
-- leaves, sparkles and dark debris.
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
--   kind  "dark" (darkens), "lime" (additive), "hot" (additive, near white)
local VORTEX = {
	{ tex = "WideDarkSlash", flip = true, kind = "dark", size = 0.9, h = 0.0, tilt = 0, spin = 0.97, rot = 55, life = 1.05 },
	{ tex = "WideDarkSlash", flip = true, kind = "dark", size = 0.82, h = 0.12, tilt = 4, spin = 1.0, rot = 65, life = 1.05 },
	{ tex = "GlowingDarkSlash", flip = true, kind = "lime", size = 1.1, h = -0.05, tilt = -3, spin = 0.98, rot = 5, life = 1 },
	{ tex = "GlowingDarkSlash", flip = true, kind = "lime", size = 1.0, h = 0.18, tilt = 6, spin = 1.03, rot = 15, life = 1 },
	{ tex = "Crescent32", kind = "lime", size = 1.05, h = 0.08, tilt = 2, spin = 1.0, rot = 10, life = 0.9 },
	{ tex = "GlowingSlash", flip = true, kind = "hot", size = 0.98, h = 0.08, tilt = 2, spin = 1.02, rot = -45, life = 0.6 },
}

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
	WindColor = Color3.fromRGB(205, 212, 222), -- grey wind ring + smoke
	LeafColor = Color3.fromRGB(70, 200, 50),
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
	FlashTime = 0.05,
	RingSize = 26, -- half-width of the ground wind-ring texture, studs
	LeafCount = 3,
	SparkleCount = 18,
	SpotCount = 8,
	SmokeCount = 18,
	DebrisCount = 10,
	DebrisColor = Color3.fromRGB(28, 32, 30),
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
		local isDark = layer.kind == "dark"
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
			LightEmission = isDark and 0 or 1,
			Brightness = layer.kind == "hot" and 1.5 or 1,
			ZOffset = isDark and -1 or (layer.kind == "hot" and 2 or 1),
			Size = seq({ { 0, size * 0.92 }, { 0.25, size }, { 1, size * 1.1 } }),
			Transparency = isDark and seq({ { 0, 0.15 }, { 0.6, 0.25 }, { 1, 1 } })
				or seq({ { 0, 0 }, { 0.6, 0.05 }, { 1, 1 } }),
			Color = if isDark
				then ColorSequence.new(p.DarkColor)
				elseif layer.kind == "hot" then colors({ { 0, p.CoreColor }, { 0.5, p.CoreColor:Lerp(p.Color, 0.4) }, { 1, p.Color } })
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

	ctx.Wait(0.015)

	-- 3. Star flash (gone by ~0.1s) ---------------------------------------------
	local flashAttachment = attachment(CFrame.new(0, 6 * s, 0)) -- high enough that the glow clears the ground
	local flashSize = p.FlashSize * s
	local rays = emitter(flashAttachment, {
		Texture = ASSETS.StarRays,
		Lifetime = NumberRange.new(p.FlashTime),
		Rotation = NumberRange.new(25, 35), -- one diagonal glare, like the reference
		LightEmission = 1,
		Brightness = 5,
		ZOffset = 3,
		Color = colors({ { 0, Color3.new(1, 1, 1) }, { 1, p.Color } }),
		Size = seq({ { 0, flashSize, flashSize * 0.2 }, { 1, flashSize * 0.85, flashSize * 0.2 } }),
		Transparency = seq({ { 0, 0 }, { 0.5, 0.1 }, { 1, 1 } }),
	})
	local glow = emitter(flashAttachment, {
		Texture = ASSETS.SoftGlow,
		Lifetime = NumberRange.new(p.FlashTime),
		LightEmission = 1,
		Brightness = 3.5,
		ZOffset = 2.5,
		Color = colors({ { 0, p.Color:Lerp(p.CoreColor, 0.6) }, { 1, p.Color } }),
		Size = seq({ { 0, flashSize * 0.5 }, { 1, flashSize * 0.45 } }),
		Transparency = seq({ { 0, 0 }, { 0.5, 0.1 }, { 1, 1 } }),
	})
	ctx.Emit(rays, 1)
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
		Lifetime = NumberRange.new(0.35),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(spin * 0.3),
		LightEmission = 0,
		Color = ColorSequence.new(p.WindColor),
		Size = seq({ { 0, ringSize * 0.65 }, { 1, ringSize * 1.0 } }),
		Transparency = seq({ { 0, 0.6 }, { 0.15, 0.45 }, { 0.5, 0.75 }, { 1, 1 } }),
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
		Lifetime = NumberRange.new(0.5, 0.8),
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
		Size = seq({ { 0, 0.25 * s }, { 1, 0.1 * s } }),
		Transparency = seq({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }),
	})
	ctx.Emit(debris, p.DebrisCount)

	ctx.Wait(p.SwirlTime)
end

return Effect
