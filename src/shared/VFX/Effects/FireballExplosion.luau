-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/FireballExplosion
-- A fireball's finishing explosion. For a frame or two a spiky flash, a white-hot core and
-- a cross flare are the biggest thing on screen; then a boiling fire body of drawn
-- fire-burst flipbooks (never one image scaling) bursts out and hangs, cooling from
-- yellow-white through orange to red, a charcoal burn-out shows through as it breaks up, and
-- mottled smoke fired in the same burst outlives it, tinted orange where the fire lights it.
-- Impact stars (colour/black/white), a black backing, streaks, a ground ring, fire comets
-- with textured trails, embers, a scorch with cooling lava cracks and a light that fades
-- while its range grows. Brightness only falls after the flash; the mass (fire, then
-- smoke) keeps growing for ~1 s.
-- Layers: flash + core + flare, stars x3, backing, fire body A/B + late wave + hot copy,
-- burn-out, smoke + fire-tinted smoke, streaks + black, ring, comets (head, 2 trails, sparks),
-- embers, scorch, cracks, crack wisps, light.
--
-- ctx.CFrame: the explosion point. The effect sits on the ground below it; LookVector
-- (toward the viewer) only orients the layout.

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
-- "Custom" = made for this project (numpy, uploaded with the Studio MCP).
local ASSETS = {
	Flash = "rbxassetid://136210055019402", -- Custom: Starburst (filled spiky shape, white)
	LavaCracks = "rbxassetid://89120608419510", -- Custom: angular cells + tendrils, baked yellow core / orange glow
	SoftGlow = "rbxassetid://284205403", -- StaticVFXTextures/Blurred Spec 11
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	TrailStreaks = "rbxassetid://13280046773", -- MigratedBeams/BeamSoftBlurredStreaks (soft wisp trail)
	TrailCore = "rbxassetid://10614304526", -- StaticVFXTextures/Sideways Spec 41 (thin needle: sharp trail)
	ImpactStar = Textures.ImpactStar, -- drawn: assets/textures/impact.py (Grid4x4)
	Glint = Textures.Glint, -- drawn: assets/textures/impact.py
	ShockRing = Textures.ShockRing, -- drawn: assets/textures/impact.py
	FireA = Textures.FireBurstA, -- drawn: assets/textures/fire.py (Grid4x4)
	FireB = Textures.FireBurstB, -- drawn: assets/textures/fire.py (Grid4x4)
	BurnOut = Textures.BurnOut, -- drawn: assets/textures/fire.py (Grid4x4)
	Smoke = Textures.DustPuff, -- drawn: assets/textures/fire.py (Grid4x4)
}

-- Comet launch directions in the layout frame (X = viewer's right, Y up, +Z toward the
-- viewer), normalised in Play: left and low, right and steep, nearly straight up.
local COMETS = {
	Vector3.new(-0.9, 0.42, 0.15),
	Vector3.new(0.7, 0.7, 0.05),
	Vector3.new(-0.34, 0.94, 0.1),
}

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(255, 125, 30), -- the fire's orange
	HotColor = Color3.fromRGB(255, 240, 200), -- white-hot start
	DeepColor = Color3.fromRGB(200, 45, 15), -- red the fire cools to
	SmokeColor = Color3.fromRGB(128, 124, 120), -- self-lit mid grey
	ScorchColor = Color3.fromRGB(20, 12, 10), -- the burnt ground
	Scale = 1,
	Radius = 7, -- studs: the blast's radius (R); the flash reaches ~2.5 R, the smoke ~2.5 R
	FireCount = 8, -- fire-burst particles per body layer (two layers + a late wave)
	SmokeCount = 6, -- per smoke layer (grey, fire-tinted)
	StreakCount = 16,
	EmberCount = 30,
	CometCount = 3, -- 0-3 fire comets
	CometSpeed = 34, -- studs/s
	CometGravity = 30, -- studs/s^2
	CometTime = 0.9, -- seconds a comet flies
	CrackTime = 2.4, -- seconds the scorch and cracks stay (they cool from orange to dark)
	LightBrightness = 12,
	LightRange = 36, -- studs the light's range grows to as it fades
}

-- Play returns once the comets have landed (~1 s); then the cracks (CrackTime after 0.3 s)
-- and the slowed smoke still fade.
Effect.Linger = 2.2

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local R = p.Radius * s

	local ground = Layers.Ground(ctx)
	local frame = Layers.Frame(ctx, ground)
	local anchor = ctx.Anchor(frame)
	local centre = Layers.Attachment(anchor, CFrame.new(0, 0.45 * R, 0)) -- the blast's heart
	local groundAtt = Layers.Attachment(anchor, CFrame.new(0, 0.12 * s, 0))
	local lowAtt = Layers.Attachment(anchor, CFrame.new(0, 0.2 * R, 0))

	-- flash: spiky body, white-hot core, cross flare -----------------------------------
	local flash = Layers.Emitter(centre, {
		Texture = ASSETS.Flash,
		Lifetime = 0.09,
		Rotation = { 0, 360 },
		LightEmission = 0,
		Brightness = 10,
		ZOffset = 4,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 0.6 * R }, { 0.3, 2.5 * R }, { 1, 2.7 * R } },
		Transparency = { { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } },
	})
	local core = Layers.Emitter(centre, {
		Texture = ASSETS.Flash,
		Lifetime = 0.05,
		Rotation = { 0, 360 },
		LightEmission = 0,
		Brightness = 40,
		ZOffset = 4.2,
		Color = Layers.WHITE,
		Size = { { 0, 0.5 * R }, { 1, 0.9 * R } },
		Transparency = { { 0, 0 }, { 1, 1 } },
	})
	local flare = Layers.Emitter(centre, {
		Texture = ASSETS.Glint,
		Lifetime = 0.08,
		LightEmission = 1,
		Brightness = 8,
		ZOffset = 4.1,
		Color = p.HotColor,
		Size = { { 0, 2.6 * R }, { 1, 3.3 * R } },
		Squash = -4,
		Transparency = { { 0, 0 }, { 1, 1 } },
	})

	-- impact stars and the black backing -----------------------------------------------
	local stars = Layers.Emitter(centre, {
		Texture = ASSETS.ImpactStar,
		Lifetime = { 0.1, 0.15 },
		Rotation = { 0, 360 },
		LightEmission = -1,
		Brightness = 5,
		ZOffset = 3,
		Color = { { 0, p.Color }, { 1, p.DeepColor } },
		Size = { { 0, 1.2 * R }, { 0.25, 2.1 * R, 0.4 * R }, { 1, 2.3 * R, 0.4 * R } },
	})
	local blackStars = Layers.Black(stars, 0.25)
	local whiteStar = Layers.White(stars, { Lifetime = { 0.06, 0.1 }, Brightness = 3, Size = { { 0, 0.5 * R }, { 1, 0.9 * R } } })
	local backing = Layers.Emitter(centre, {
		Texture = ASSETS.SoftGlow,
		Lifetime = 0.4,
		LightEmission = 0,
		ZOffset = -2,
		Color = Layers.BLACK,
		Size = { { 0, 2.2 * R }, { 1, 3.4 * R } },
		Transparency = { { 0, 0.35 }, { 1, 1 } },
	})

	-- fire body: overlapping drawn bursts that shoot out, then hang and boil -------------
	local fireColor = {
		{ 0, p.HotColor }, { 0.25, p.Color:Lerp(p.HotColor, 0.35) }, { 0.6, p.Color:Lerp(p.DeepColor, 0.5) }, { 1, p.DeepColor:Lerp(p.ScorchColor, 0.4) },
	}
	local function fireLayer(texture, zOffset)
		return Layers.Emitter(centre, {
			Texture = texture,
			Lifetime = { 0.45, 0.8 },
			Speed = { 12 * R / 5, 28 * R / 5 },
			SpreadAngle = 180,
			Drag = 4,
			Rotation = { 0, 360 },
			RotSpeed = { -40, 40 },
			LightEmission = 0.2,
			Brightness = 5,
			ZOffset = zOffset,
			Color = fireColor,
			Size = { { 0, 0.6 * R, 0.15 * R }, { 0.3, 1.6 * R, 0.35 * R }, { 1, 1.8 * R, 0.35 * R } },
			-- keep it solid: the sheet breaks itself apart
		})
	end
	local fireA = fireLayer(ASSETS.FireA, 1)
	local fireB = fireLayer(ASSETS.FireB, 1.05)
	-- a slower, bigger late wave: the mass keeps growing after the flash
	local fireLate = Layers.Twin(fireA, {
		Lifetime = { 0.7, 1 },
		Speed = { 6 * R / 5, 14 * R / 5 },
		Drag = 3,
		EmissionDirection = "Top",
		SpreadAngle = 70,
		Size = { { 0, 1 * R, 0.2 * R }, { 0.35, 2.2 * R, 0.4 * R }, { 1, 2.5 * R, 0.4 * R } },
		ZOffset = 0.9,
	})
	local fireHot = Layers.Twin(fireB, {
		Lifetime = { 0.2, 0.3 },
		Brightness = 18,
		ZOffset = 1.5,
		Size = { { 0, 0.4 * R }, { 0.3, 1.1 * R, 0.2 * R }, { 1, 1.2 * R } },
	})
	-- burn-out: charcoal with glowing cracks just behind the body, seen as it breaks up
	local burnOut = Layers.Emitter(centre, {
		Texture = ASSETS.BurnOut,
		Lifetime = { 0.5, 0.7 },
		Speed = { 1 * R / 5, 3 * R / 5 },
		SpreadAngle = 180,
		Drag = 4,
		Rotation = { 0, 360 },
		LightEmission = 0,
		Brightness = 2.5,
		ZOffset = 0.5,
		Color = { { 0, p.Color:Lerp(p.DeepColor, 0.3) }, { 1, p.DeepColor } },
		Size = { { 0, 1.4 * R }, { 1, 1.8 * R } },
		Transparency = { { 0, 0.1 }, { 0.6, 0.3 }, { 1, 1 } },
	})

	-- smoke: the same burst, living 1.5-3 times as long, slowed; one twin lit by the fire --
	local function smokeLayer(color, zOffset)
		return Layers.Emitter(centre, {
			Texture = ASSETS.Smoke,
			Lifetime = { 0.9, 1.4 },
			Speed = { 8 * R / 5, 16 * R / 5 },
			SpreadAngle = 180,
			Drag = 6,
			Acceleration = Vector3.new(0, 2 * s, 0),
			Rotation = { 0, 360 },
			RotSpeed = { -20, 20 },
			LightEmission = 0,
			Brightness = 1.6,
			ZOffset = zOffset,
			Color = color,
			Size = { { 0, 0.8 * R, 0.2 * R }, { 1, 2.1 * R, 0.4 * R } },
			-- daylight: fairly solid at its peak, so it keeps its own grey against the sky
			Transparency = { { 0, 0.75 }, { 0.15, 0.3 }, { 1, 1.15 } },
		})
	end
	local smoke = smokeLayer(p.SmokeColor, 0)
	local fireSmoke = smokeLayer({ { 0, p.SmokeColor }, { 0.25, p.Color }, { 1, p.SmokeColor } }, 0.05)

	-- streaks, ring, embers -------------------------------------------------------------
	local streaks = Layers.Emitter(centre, {
		Texture = ASSETS.SoftGlow,
		Orientation = "VelocityParallel",
		Lifetime = { 0.2, 0.35 },
		Speed = { 15 * R, 40 * R },
		SpreadAngle = 180,
		Drag = 10,
		LightEmission = 0,
		Brightness = 8,
		ZOffset = 3,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 0.25 * R, 0.1 * R }, { 1, 0 } },
		Squash = { { 0, 3 }, { 1, 1 } },
	})
	local blackStreaks = Layers.Black(streaks, 0.1, { Speed = { 8 * R, 20 * R } })
	local ring = Layers.Emitter(groundAtt, {
		Flat = true,
		Texture = ASSETS.ShockRing,
		Lifetime = 0.4,
		Rotation = { 0, 360 },
		LightEmission = 0.3,
		Brightness = 3,
		ZOffset = 0.5,
		Color = p.HotColor,
		Size = { { 0, 0.4 * R }, { 0.4, 2.5 * R }, { 1, 3 * R } },
		Transparency = { { 0, 0 }, { 1, 1.3 } },
	})
	local embers = Layers.Emitter(lowAtt, {
		Texture = ASSETS.Speck,
		Lifetime = { 0.75, 1.6 },
		Speed = { 2 * R, 15 * R },
		SpreadAngle = 180,
		Drag = 10,
		Acceleration = Vector3.new(0, 3 * s, 0),
		LightEmission = 1,
		Brightness = 2,
		ZOffset = 2,
		Color = { { 0, p.HotColor }, { 0.4, p.Color }, { 1, p.DeepColor } },
		Size = { { 0, 0.05 * R, 0.02 * R }, { 0.8, 0.04 * R }, { 1, 0 } },
	})

	-- scorch, cracks and wisps: ground marks that cool over CrackTime ---------------------
	local scorch = Layers.Emitter(groundAtt, {
		Flat = true,
		Texture = ASSETS.SoftGlow,
		Lifetime = p.CrackTime,
		LightEmission = 0,
		ZOffset = 0.1,
		Color = p.ScorchColor,
		Size = { { 0, 1.4 * R }, { 0.05, 1.8 * R }, { 1, 1.9 * R } },
		Transparency = { { 0, 1 }, { 0.05, 0.3 }, { 0.7, 0.45 }, { 1, 1 } },
	})
	local cracks = Layers.Emitter(groundAtt, {
		Flat = true,
		Texture = ASSETS.LavaCracks,
		Lifetime = p.CrackTime,
		Rotation = { -15, 15 },
		LightEmission = 1,
		Brightness = 2,
		ZOffset = 0.2,
		-- the baked yellow-orange cools to deep red, then dark
		Color = { { 0, Layers.WHITE }, { 0.35, Color3.new(1, 0.75, 0.6) }, { 0.75, Color3.new(0.8, 0.25, 0.15) }, { 1, Color3.new(0.25, 0.06, 0.04) } },
		Size = { { 0, 0.6 * R }, { 0.05, 0.85 * R }, { 1, 0.85 * R } },
		Transparency = { { 0, 1 }, { 0.04, 0 }, { 0.6, 0.15 }, { 1, 1 } },
	})
	local wispArea = ctx.Anchor(frame * CFrame.new(0, 0.3 * s, 0))
	wispArea.Size = Vector3.new(1.3 * R, 0.2, 0.9 * R)
	local wisps = Layers.Emitter(wispArea, {
		Shape = "Box",
		Texture = ASSETS.Smoke,
		Orientation = "FacingCameraWorldUp",
		EmissionDirection = "Top",
		SpreadAngle = 15,
		Lifetime = { 1, 1.4 },
		Speed = { 0.25 * R, 0.4 * R },
		Rotation = { -15, 15 },
		LightEmission = 0,
		Brightness = 1.4,
		Color = p.SmokeColor,
		Size = { { 0, 0.15 * R }, { 1, 0.3 * R, 0.05 * R } },
		Squash = 1.2, -- tall and thin
		Transparency = { { 0, 1 }, { 0.2, 0.45 }, { 1, 1 } },
	})

	-- comets: a hot head, a sharp and a soft textured trail, shed sparks -----------------
	local timeScale = math.max(ctx.TimeScale, 1e-3)
	local comets = {}
	local gravity = Vector3.new(0, -p.CometGravity * s, 0)
	for i = 1, math.clamp(math.floor(p.CometCount), 0, #COMETS) do
		local head = Layers.Attachment(anchor)
		local edgeA = Layers.Attachment(anchor)
		local edgeB = Layers.Attachment(anchor)
		local wispA = Layers.Attachment(anchor)
		local wispB = Layers.Attachment(anchor)
		local glow = Layers.Emitter(head, {
			Texture = ASSETS.SoftGlow,
			LockedToPart = true,
			Lifetime = p.CometTime + 0.05,
			LightEmission = 0,
			Brightness = 6,
			ZOffset = 1,
			Color = p.HotColor,
			Size = 0.12 * R,
			Transparency = { { 0, 0 }, { 0.85, 0 }, { 1, 1 } },
		})
		local sharp = Instance.new("Trail")
		Layers.Apply(sharp, {
			Attachment0 = edgeA,
			Attachment1 = edgeB,
			Texture = ASSETS.TrailCore,
			Lifetime = 0.22 / timeScale,
			MinLength = 0.05,
			FaceCamera = true,
			LightEmission = 0,
			Brightness = 10,
			Color = { { 0, p.HotColor }, { 1, p.Color } },
			-- clear for the first bit behind the head, so the head reads on its own
			Transparency = { { 0, 1 }, { 0.15, 0 }, { 1, 1 } },
			WidthScale = { { 0, 1 }, { 1, 0 } },
		})
		sharp.Parent = anchor
		local soft = Instance.new("Trail")
		Layers.Apply(soft, {
			Attachment0 = wispA,
			Attachment1 = wispB,
			Texture = ASSETS.TrailStreaks,
			Lifetime = 0.4 / timeScale,
			MinLength = 0.05,
			FaceCamera = true,
			LightEmission = 0.6,
			Brightness = 1.5,
			Color = { { 0, p.Color }, { 0.5, p.DeepColor }, { 1, p.SmokeColor } },
			Transparency = { { 0, 0.4 }, { 1, 1 } },
			WidthScale = { { 0, 0.6 }, { 0.4, 1 }, { 1, 0 } }, -- bulges in the middle
		})
		soft.Parent = anchor
		local sparks = Layers.Emitter(head, {
			Texture = ASSETS.Speck,
			Rate = 40,
			Enabled = false,
			Lifetime = { 0.25, 0.45 },
			Speed = { 1 * s, 4 * s },
			SpreadAngle = 180,
			Drag = 3,
			Acceleration = Vector3.new(0, -10 * s, 0),
			LightEmission = 1,
			Brightness = 2,
			Color = { { 0, p.HotColor }, { 1, p.Color } },
			Size = { { 0, 0.15 * s }, { 1, 0 } },
		})
		table.insert(comets, {
			Head = head,
			Edges = { edgeA, edgeB, wispA, wispB },
			Trails = { sharp, soft },
			Glow = glow,
			Sparks = sparks,
			Velocity = frame:VectorToWorldSpace(COMETS[i].Unit) * p.CometSpeed * s * (0.9 + 0.2 * math.random()),
		})
	end
	local function placeComets(age)
		for _, comet in comets do
			local start = centre.WorldPosition
			local pos = start + comet.Velocity * age + gravity * (0.5 * age * age)
			local vel = comet.Velocity + gravity * age
			local side = vel:Cross(Vector3.yAxis)
			if side.Magnitude < 1e-3 then
				side = Vector3.xAxis
			end
			side = side.Unit
			comet.Head.WorldPosition = pos
			comet.Edges[1].WorldPosition = pos + side * 0.15 * R
			comet.Edges[2].WorldPosition = pos - side * 0.15 * R
			comet.Edges[3].WorldPosition = pos + side * 0.35 * R
			comet.Edges[4].WorldPosition = pos - side * 0.35 * R
		end
	end

	local light = Layers.Light(centre, { Color = p.Color })
	local cometStart = 0.035

	Layers.Timeline(ctx, {
		{ 0, function()
			ctx.Emit(flash, 1)
			ctx.Emit(core, 1)
			ctx.Emit(flare, 1)
			Layers.Pop(ctx, light, p.LightBrightness, 6 * s, p.LightRange * s, 0.9)
		end },
		{ 0.03, function()
			ctx.Emit(stars, 3)
			ctx.Emit(blackStars, 3)
			ctx.Emit(whiteStar, 1)
			ctx.Emit(fireA, p.FireCount)
			ctx.Emit(fireB, p.FireCount)
			ctx.Emit(fireHot, 4)
		end },
		{ cometStart, function()
			placeComets(0)
			for _, comet in comets do
				ctx.Emit(comet.Glow, 1)
				comet.Sparks.TimeScale = ctx.TimeScale
				comet.Sparks.Enabled = true
			end
			-- the comets fly on their own clock, a step per rendered frame
			task.spawn(function()
				local age = 0
				while age < p.CometTime and ctx.Folder.Parent do
					age += ctx.Wait(1 / 60)
					placeComets(math.min(age, p.CometTime))
				end
				for _, comet in comets do
					comet.Sparks.Enabled = false
					for _, trail in comet.Trails do
						trail.Enabled = false
					end
				end
			end)
		end },
		{ 0.06, function()
			ctx.Emit(backing, 1)
			Layers.Emit(ctx, smoke, p.SmokeCount, 0.75)
			Layers.Emit(ctx, fireSmoke, p.SmokeCount, 0.75)
			ctx.Emit(streaks, p.StreakCount)
			ctx.Emit(blackStreaks, math.ceil(p.StreakCount / 3))
			ctx.Emit(ring, 1)
			ctx.Emit(embers, p.EmberCount)
		end },
		{ 0.1, function()
			ctx.Emit(fireLate, math.ceil(p.FireCount * 0.75))
		end },
		{ 0.26, function()
			ctx.Emit(burnOut, 2)
		end },
		{ 0.3, function()
			ctx.Emit(scorch, 1)
			ctx.Emit(cracks, 1)
		end },
		{ 0.7, function()
			Layers.Emit(ctx, wisps, 4, 0.8)
		end },
		{ 1.0, function()
			Layers.Emit(ctx, wisps, 3, 0.8)
		end },
		{ cometStart + p.CometTime, function() end },
	})
end

return Effect
