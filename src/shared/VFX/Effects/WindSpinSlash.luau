-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/WindSpinSlash
-- Green wind spin-slash around the caster. Layers: a steeply tilted vortex of spinning
-- crescent strokes (dark green body behind solid lime, a thin additive hot stroke, black
-- ink strokes woven through), black and lime streaks plus hot spots shed along the
-- spinning arc so the eye follows the blade, a spiky flash over a squashed flare line, a
-- grey wind ring and swirl lines on the ground, mottled grey wind-smoke, rising thin
-- crescents, leaves, sparkles, glow spots and dark shards, and a light pop.
--
-- ctx.CFrame: the caster's root. The vortex is centred on the ground below it.
-- It tilts toward SwirlTiltYaw (degrees from the caster's facing): that side
-- dips to the ground and the opposite side rises.
--
-- Every vortex layer is one flat particle (Flat: VelocityPerpendicular, tiny speed) so it
-- lies in the tilted plane and spins with RotSpeed; a layer's dark copy shares its start
-- angle so the two line up. ParticleEmitter.Size is a half-width.
-- Scattered layers (smoke, sparkles, spots) emit from invisible Disc-shaped parts: moving
-- an Attachment between Emit calls in one frame does not move the spawn point.

local VFX = script.Parent.Parent
local MeshParticles = require(VFX:WaitForChild("MeshParticles"))
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	WideDarkSlash = "rbxassetid://104673447334638", -- FlipbookTextures/Wide Dark Slash (Grid4x4)
	GlowingDarkSlash = "rbxassetid://107491452097107", -- FlipbookTextures/Medium Glowing Dark Slash (Grid4x4)
	GlowingSlash = "rbxassetid://13580352351", -- FlipbookTextures/Glowing Slash (Grid4x4)
	ThinSlash = "rbxassetid://85263893313331", -- FlipbookTextures/Thin Basic Slash (Grid4x4)
	StreakySlash = "rbxassetid://118897571793559", -- FlipbookTextures/Shaded Slash 5 (Grid4x4)
	Crescent32 = "rbxassetid://17388445727", -- StaticVFXTextures/Crescent32
	Crescent18 = "rbxassetid://17388365742", -- StaticVFXTextures/Crescent18
	SmokeyShockwave = "rbxassetid://12318427672", -- StaticVFXTextures/Smokey Shockwave
	Swirls21 = "rbxassetid://130391463304711", -- StaticVFXTextures/Swirls21
	Flash = "rbxassetid://136210055019402", -- Custom: Starburst (filled spiky shape, white)
	SoftGlow = "rbxassetid://284205403", -- StaticVFXTextures/Blurred Spec 11
	Sparkle = "rbxassetid://16444981264", -- StaticVFXTextures/Star153
	LeafMesh = "rbxassetid://5129539702", -- MigratedMeshes/Leaf (native 5.45 x 1.61 x 11.0)
	Glint = Textures.Glint, -- drawn: assets/textures/impact.py
	Smoke = Textures.DustPuff, -- drawn: assets/textures/fire.py (Grid4x4)
	Splinters = Textures.Splinters, -- drawn: assets/textures/impact.py (Grid4x4)
}

local LEAF_MESH_LENGTH = 11 -- native Z length of LeafMesh, for scaling

-- Vortex layers, one flat spinning crescent particle each.
--   size  fraction of SwirlRadius            h     height offset (fraction of radius)
--   tilt  extra tilt (deg)                   spin  multiplier on SpinSpeed
--   rot   start angle offset (deg). Each texture's arc sits at a different angle in
--         its quad, so these phase the arcs into one ~180 deg crescent (an open C)
--   life  multiplier on SwirlTime            grid  4 = 4x4 flipbook played once
--   kind  "dark" (solid dark body), "lime" (solid colour), "hot" (thin additive
--         highlight), "ink" (near-black thin strokes drawn over the lime)
--   alpha starting transparency for "ink" layers (default 0.05)
local VORTEX = {
	{ tex = "WideDarkSlash", grid = 4, kind = "dark", size = 0.9, h = 0.0, tilt = 0, spin = 0.97, rot = -35, life = 1.08 },
	{ tex = "WideDarkSlash", grid = 4, kind = "dark", size = 0.82, h = 0.12, tilt = 4, spin = 1.0, rot = -25, life = 1.08 },
	{ tex = "GlowingDarkSlash", grid = 4, kind = "lime", size = 1.1, h = -0.05, tilt = -3, spin = 0.98, rot = 5, life = 1 },
	{ tex = "GlowingDarkSlash", grid = 4, kind = "lime", size = 1.0, h = 0.18, tilt = 6, spin = 1.03, rot = 15, life = 1 },
	{ tex = "Crescent32", kind = "lime", size = 1.05, h = 0.08, tilt = 2, spin = 1.0, rot = 10, life = 0.9 },
	{ tex = "GlowingSlash", grid = 4, kind = "hot", size = 0.98, h = 0.08, tilt = 2, spin = 1.02, rot = -45, life = 0.8 },
	{ tex = "ThinSlash", grid = 4, kind = "ink", size = 1.04, h = 0.05, tilt = 2, spin = 1.0, rot = 15, life = 0.9 },
	{ tex = "ThinSlash", grid = 4, kind = "ink", size = 0.9, h = 0.12, tilt = 4, spin = 1.04, rot = 35, life = 0.85 },
	{ tex = "StreakySlash", grid = 4, kind = "ink", size = 1.08, h = 0.0, tilt = 0, spin = 0.99, rot = 25, life = 0.95, alpha = 0.4 },
}

-- Which way the shed streaks orbit (+1/-1) so they travel with the spinning
-- arcs; ParticleEmitter RotSpeed and the orbit angle turn opposite ways
local ORBIT_SIGN = -1

local leafTemplate
local function getLeafTemplate()
	if not leafTemplate then
		local part = Layers.Quiet(Instance.new("Part"))
		part.Name = "Leaf"
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
	LimeBrightness = 3.5, -- solid lime layers (LightEmission 0): Brightness carries the glow
	FlashSize = 11, -- studs, half-width of the spiky flash at its peak
	FlashTime = 0.07, -- seconds the flash lasts
	StreakTime = 0.22, -- seconds black streaks and hot spots are shed along the arc
	StreakCount = 3, -- black streaks shed per frame while StreakTime runs
	RingSize = 26, -- half-width of the ground wind-ring texture, studs
	LeafCount = 3,
	LeafRiseCount = 2, -- upright leaves rising slowly inside the vortex
	SparkleCount = 18,
	SpotCount = 8,
	SmokeCount = 12,
	DebrisCount = 10,
	DebrisColor = Color3.fromRGB(52, 42, 34), -- dark brown chips
	LightBrightness = 6,
	LightRange = 22,
}

Effect.Linger = 1.75 -- smoke slowed to 0.8x (up to 1.4 / 0.8 s) and the leaves

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local radius = p.SwirlRadius * s
	local spin = p.SpinSpeed * p.SpinDirection

	local ground = Layers.Ground(ctx)
	local look = ctx.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local anchor = ctx.Anchor(CFrame.new(ground) * CFrame.Angles(0, yaw, 0))
	local function attachment(cf)
		return Layers.Attachment(anchor, cf)
	end

	local swirlCenter = CFrame.new(0, p.SwirlHeight * s, 0)
	local function tilted(extraHeight, extraTilt)
		return swirlCenter
			* CFrame.new(0, extraHeight, 0)
			* CFrame.Angles(0, math.rad(p.SwirlTiltYaw), 0)
			* CFrame.Angles(-math.rad(p.SwirlTilt + extraTilt), 0, 0)
	end

	-- 1. Vortex body ----------------------------------------------------------------
	local startAngle = p.SwirlStartAngle + math.random(-20, 20)
	local layerAttachments = {} -- layers with the same height and tilt share one
	local vortex = {}
	for _, layer in VORTEX do
		local key = layer.h .. ":" .. layer.tilt
		layerAttachments[key] = layerAttachments[key] or attachment(tilted(layer.h * radius, layer.tilt))
		local kind = layer.kind
		local size = radius * layer.size
		local alpha = layer.alpha or 0.05
		local e = Layers.Emitter(layerAttachments[key], {
			Flat = true,
			Texture = { Id = ASSETS[layer.tex], Grid = layer.grid },
			Speed = 8 * s, -- drifts ~2.5 studs along its normal
			Drag = 3,
			Lifetime = p.SwirlTime * layer.life,
			Rotation = startAngle + layer.rot,
			RotSpeed = spin * layer.spin,
			-- solid colour (LightEmission 0): the dark-pixel slash sheets need 0 or 1, and
			-- additive lime washes out over bright ground; only the thin hot stroke adds light
			LightEmission = if kind == "hot" then 1 else 0,
			Brightness = if kind == "lime" then p.LimeBrightness elseif kind == "hot" then 2 else 1,
			ZOffset = if kind == "dark" then -1 elseif kind == "ink" then 1.5 elseif kind == "hot" then 2 else 1,
			Size = { { 0, size * 0.92 }, { 0.25, size }, { 1, size * 1.1 } },
			Transparency = if kind == "dark"
				then { { 0, 0.15 }, { 0.6, 0.25 }, { 1, 1 } }
				elseif kind == "ink" then { { 0, alpha }, { 0.55, alpha + 0.15 }, { 1, 1 } }
				else { { 0, 0 }, { 0.6, 0.05 }, { 1, 1 } },
			Color = if kind == "dark"
				then p.DarkColor
				elseif kind == "ink" then p.InkColor
				elseif kind == "hot" then { { 0, p.CoreColor }, { 0.5, p.CoreColor:Lerp(p.Color, 0.4) }, { 1, p.Color } }
				else p.Color,
		})
		table.insert(vortex, e)
	end

	-- 2. Streaks and hot spots shed along the spinning arc ------------------------------
	-- One attachment orbits the vortex at its spin rate, a step per frame, so the eye
	-- follows the blade round: black wedges along the arc's travel, lime needles, hot spots.
	local orbitCenter = tilted(0.08 * radius, 2)
	local orbit = attachment(orbitCenter)
	local direction = if p.SpinDirection > 0 then "Front" else "Back"
	local inkStreaks = Layers.Emitter(orbit, {
		Texture = ASSETS.SoftGlow,
		Orientation = "VelocityParallel",
		EmissionDirection = direction,
		SpreadAngle = 12,
		Speed = { 6 * s, 14 * s },
		Drag = 8,
		Lifetime = { 0.12, 0.22 },
		LightEmission = 0,
		ZOffset = 2,
		Color = p.InkColor,
		Size = { { 0, 0.9 * s, 0.25 * s }, { 0.6, 0.7 * s }, { 1, 0 } },
		Squash = 2.5, -- streaks along the travel
		Transparency = { { 0, 0.05 }, { 0.7, 0.2 }, { 1, 1 } },
	})
	local limeStreaks = Layers.Emitter(orbit, {
		Texture = ASSETS.SoftGlow,
		Orientation = "VelocityParallel",
		EmissionDirection = direction,
		SpreadAngle = 15,
		Speed = { 25 * s, 40 * s },
		Drag = 6,
		Lifetime = { 0.1, 0.18 },
		LightEmission = 0,
		Brightness = 5,
		ZOffset = 2,
		Color = { { 0, p.CoreColor }, { 1, p.Color } },
		Size = { { 0, 0.7 * s, 0.2 * s }, { 1, 0 } },
		Squash = { { 0, 3 }, { 1, 1.5 } },
	})
	local hotSpots = Layers.Emitter(orbit, {
		Texture = ASSETS.SoftGlow,
		Lifetime = { 0.04, 0.07 },
		LightEmission = 1,
		Brightness = 3,
		ZOffset = 2.2,
		Color = { { 0, p.CoreColor }, { 1, p.Color } },
		Size = { { 0, 1.1 * s, 0.3 * s }, { 1, 0.3 * s } },
		Transparency = { { 0, 0.1 }, { 1, 1 } },
	})

	-- 3. Flash: a filled spiky shape over a squashed flare line, gone by ~0.08 s --------
	local flashAttachment = attachment(CFrame.new(0, 6 * s, 0)) -- high enough to clear the ground
	local flashSize = p.FlashSize * s
	local flash = Layers.Emitter(flashAttachment, {
		Texture = ASSETS.Flash,
		Lifetime = p.FlashTime,
		Rotation = { 0, 360 },
		LightEmission = 0,
		Brightness = 6,
		ZOffset = 3,
		Color = { { 0, p.CoreColor }, { 1, p.Color } },
		Size = { { 0, flashSize * 0.25 }, { 0.3, flashSize }, { 1, flashSize * 1.05 } },
		Transparency = { { 0, 0 }, { 0.65, 0.1 }, { 1, 1 } },
	})
	local flare = Layers.Emitter(flashAttachment, {
		Texture = ASSETS.Glint,
		Lifetime = p.FlashTime * 0.85,
		Rotation = { -50, -40 }, -- the long thin ray up and to the right
		LightEmission = 1,
		Brightness = 6,
		ZOffset = 3.1,
		Color = { { 0, Layers.WHITE }, { 1, p.CoreColor } },
		Size = { { 0, flashSize * 1.1 }, { 1, flashSize * 1.4 } },
		Squash = -3,
		Transparency = { { 0, 0 }, { 1, 1 } },
	})
	local light = Layers.Light(attachment(CFrame.new(0, 2 * s, 0)), { Color = p.Color })

	-- 4. Ground: wind ring, swirl lines, wind-smoke -------------------------------------
	local groundAttachment = attachment(CFrame.new(0, 0.2 * s, 0))
	local ringSize = p.RingSize * s
	local ring = Layers.Emitter(groundAttachment, {
		Flat = true,
		Texture = ASSETS.SmokeyShockwave,
		Lifetime = 0.6,
		Rotation = { 0, 360 },
		RotSpeed = spin * 0.15,
		LightEmission = 0,
		Brightness = 1.3,
		Color = p.WindColor,
		Size = { { 0, ringSize * 0.75 }, { 1, ringSize * 1.35 } },
		Transparency = { { 0, 0.7 }, { 0.12, 0.5 }, { 0.4, 0.75 }, { 1, 1 } },
	})
	local ringLines = Layers.Emitter(groundAttachment, {
		Flat = true,
		Texture = ASSETS.Swirls21,
		Lifetime = 0.6,
		Rotation = { 0, 360 },
		RotSpeed = spin * 0.3,
		LightEmission = 1,
		Brightness = 1,
		ZOffset = 0.5,
		Color = p.WindColor,
		Size = { { 0, ringSize * 0.65 }, { 1, ringSize * 1.0 } },
		Transparency = { { 0, 0.6 }, { 0.15, 0.4 }, { 0.6, 0.65 }, { 1, 1.1 } },
	})

	local function scatterPart(discRadius, height)
		local part = ctx.Anchor(anchor.CFrame * CFrame.new(0, height, 0))
		part.Size = Vector3.new(discRadius * 2, 0.1, discRadius * 2)
		return part
	end
	-- self-lit mottled smoke, a grey pair (warm and cool), fairly solid so it keeps its grey
	local smokeRing = scatterPart(radius * 1.5, 0.4 * s)
	local function smokeLayer(color)
		return Layers.Emitter(smokeRing, {
			Flat = true,
			Shape = "Disc",
			ShapePartial = 0.8, -- mostly fills the disc, thinning toward the centre
			Texture = ASSETS.Smoke,
			Lifetime = { 0.9, 1.4 },
			Rotation = { 0, 360 },
			RotSpeed = { -30, 30 },
			LightEmission = 0,
			Brightness = 1.5,
			Color = color,
			Size = { { 0, 4 * s, 1 * s }, { 1, 10 * s, 2 * s } },
			Transparency = { { 0, 1 }, { 0.15, 0.55 }, { 1, 1 } },
		})
	end
	local smoke = smokeLayer(p.WindColor)
	local warmSmoke = smokeLayer(p.WindColor:Lerp(Color3.fromRGB(215, 200, 170), 0.5))

	-- 5. Sparkles, rising thin crescents, glow spots, shards -----------------------------
	local area = scatterPart(radius * 0.95, 0.5 * s)
	local sparkles = Layers.Emitter(area, {
		Shape = "Disc",
		EmissionDirection = "Top",
		Texture = ASSETS.Sparkle,
		Lifetime = { 0.6, 1.2 },
		Speed = { 2 * s, 10 * s },
		SpreadAngle = 30,
		Drag = 3,
		Acceleration = Vector3.new(0, 2, 0),
		LightEmission = 1,
		Brightness = 3,
		ZOffset = 2,
		Color = { { 0, p.Color:Lerp(p.CoreColor, 0.3) }, { 1, p.Color } },
		Size = { { 0, 0 }, { 0.1, 0.5 * s, 0.2 * s }, { 0.5, 0.3 * s }, { 0.7, 0.45 * s }, { 1, 0 } },
		Transparency = { { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } },
	})
	local lines = Layers.Emitter(attachment(tilted(radius * 0.2, 4)), {
		Flat = true,
		Texture = ASSETS.Crescent18,
		SpreadAngle = 4,
		Speed = { 8 * s, 12 * s },
		Drag = 4,
		Lifetime = { 0.18, 0.22 },
		Rotation = { startAngle, startAngle + 20 },
		RotSpeed = spin * 0.9,
		LightEmission = 1, -- thin white-lime strokes: the effect's white shapes
		Brightness = 1.5,
		ZOffset = 1.5,
		Color = { { 0, p.CoreColor }, { 0.3, p.Color }, { 1, p.Color } },
		Size = { { 0, radius }, { 1, radius * 1.15 } },
		Transparency = { { 0, 1 }, { 0.1, 0 }, { 0.5, 0.1 }, { 1, 1 } },
	})
	local spots = Layers.Emitter(area, {
		Flat = true,
		Shape = "Disc",
		Texture = ASSETS.SoftGlow,
		Lifetime = { 0.3, 0.45 },
		LightEmission = 1,
		Color = p.Color,
		Size = { { 0, 1.3 * s, 0.4 * s }, { 1, 1 * s } },
		Transparency = { { 0, 0.3 }, { 1, 1 } },
	})
	local debris = Layers.Emitter(groundAttachment, {
		Texture = ASSETS.Splinters,
		Lifetime = { 0.5, 0.8 },
		Speed = { 18 * s, 28 * s },
		SpreadAngle = 60,
		Drag = 2,
		Acceleration = Vector3.new(0, -60, 0),
		Rotation = { 0, 360 },
		RotSpeed = { -360, 360 },
		LightEmission = 0,
		Color = p.DebrisColor,
		Size = { { 0, 0.6 * s, 0.25 * s }, { 1, 0.35 * s } },
	})

	local leaf = getLeafTemplate()
	leaf.Color = p.LeafColor
	leaf.Mesh.Scale = Vector3.one * (4.5 * s / LEAF_MESH_LENGTH)
	local function leaves()
		-- one burst per leaf (Burst sprays a cone round one direction), evenly round the caster
		local leafAngle = math.random() * math.pi * 2
		for i = 1, p.LeafCount do
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
				Transparency = Layers.Seq({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }),
			})
		end
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
				Transparency = Layers.Seq({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }),
			})
		end
	end

	-- streaks: a step per rendered frame while StreakTime runs
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
			elapsed += ctx.Wait(1 / 60)
		end
	end)

	Layers.Timeline(ctx, {
		{ 0, function()
			for _, e in vortex do
				ctx.Emit(e, 1)
			end
			Layers.Pop(ctx, light, p.LightBrightness, 6 * s, p.LightRange * s, 0.35)
		end },
		{ 0.01, function()
			ctx.Emit(flash, 1)
			ctx.Emit(flare, 1)
		end },
		{ 0.025, function()
			ctx.Emit(ring, 1)
			ctx.Emit(ringLines, 1)
			Layers.Emit(ctx, smoke, math.ceil(p.SmokeCount / 2), 0.8)
			Layers.Emit(ctx, warmSmoke, math.floor(p.SmokeCount / 2), 0.8)
			leaves()
		end },
		{ 0.055, function()
			ctx.Emit(sparkles, p.SparkleCount)
			ctx.Emit(lines, 2)
			ctx.Emit(spots, p.SpotCount)
		end },
		{ 0.115, function()
			ctx.Emit(debris, p.DebrisCount)
		end },
		{ 0.115 + p.SwirlTime, function() end },
	})
end

return Effect
