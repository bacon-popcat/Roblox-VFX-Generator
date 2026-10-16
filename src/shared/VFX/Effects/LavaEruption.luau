-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/LavaEruption
-- A lava fissure: a crack splits the ground with streaks, flung rocks, small upright
-- flames and dark smoke that shoots up, and glows red; then a tall curtain of thin flame
-- tongues erupts from it inside a wide wind swirl, burns for ~2.2 s around a tapered
-- central flame, narrows to a thin bundle and dies.
-- Layers: crack decal (dark rift, hot line, red pool), precursor streaks/rocks/flames/ring
-- curls/smoke/embers, eruption spike row and base splash, wind arcs, flame-veil beams, flame
-- tongues (taller in the centre) + soft flame body + dark tongues, central flame with a
-- yellow core, glow and faint streak, hot ground line, curls, dark flecks, embers, light.
--
-- ctx.CFrame: the fissure sits on the ground below it and runs across the view (along
-- ctx.CFrame's RightVector); LookVector points at the viewer. WallLength sizes the fissure,
-- curtain, wind, column and smoke spread (the curtain is ~0.65-0.95x as tall as the fissure
-- is long); Scale sizes everything, including the precursor bits. Plain Luau.
--
-- Every channel (rates, emitter widths, beam widths, light) is driven by one per-frame
-- loop through ctx.Wait, so slow-mo and VFXScrub freezes work (beam texture scroll keeps
-- moving during a freeze).

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	Rift = "rbxassetid://130357872021925", -- StaticVFXTextures/dark glowing rift (long thin jagged crack, horizontal)
	BranchCrack = "rbxassetid://94057358812878", -- StaticVFXTextures/simple crack (star of branching cracks)
	Rocks = "rbxassetid://14305019062", -- FlipbookTextures/Random Rocks (Grid4x4, one rock per cell)
	FlameStreak = "rbxassetid://104267390423468", -- StaticVFXTextures/Line Spec 3 (tall flame-shaped streak)
	FlameWisps = "rbxassetid://125449362531870", -- MigratedBeams/BeamFlameWisps (vertical flame tongues)
	FlamePeaks = "rbxassetid://118613370531472", -- MigratedBeams/BeamFlamePeaks (flame peaks rising from a base)
	FireColumn = "rbxassetid://11767688250", -- MigratedBeams/BeamOrangeFireColumn (orange column, yellow core, coloured)
	GlowCore = "rbxassetid://12781750620", -- MigratedBeams/BeamSoftGlowCore (soft vertical glow)
	FlamePillar = "rbxassetid://70418763522849", -- FlipbookTextures/Upwards flame pillar (Grid4x4)
	FireTower = "rbxassetid://18456244650", -- FlipbookTextures/Fire Tower (Grid4x4, smooth thin upright wisps)
	FlameBody = "rbxassetid://107423905441539", -- FlipbookTextures/Blurry glowing flame (Grid4x4, soft flame blobs)
	SoftSmoke = "rbxassetid://111394301752764", -- StaticVFXTextures/smoke 41 (soft round puff)
	FlameWisp = "rbxassetid://16504098653", -- FlipbookTextures/Basic Flame Wisp (Grid4x4)
	RingCurl = "rbxassetid://77001323190674", -- FlipbookTextures/dark fire spec (Grid4x4, 128 cells on a 512 sheet; hollow curls)
	Swirl = "rbxassetid://130391463304711", -- StaticVFXTextures/Swirls21 (crescent arcs)
	LineFlare = "rbxassetid://103854278038347", -- StaticVFXTextures/Blurry Horizontal Flare
	SoftGlow = "rbxassetid://284205403", -- StaticVFXTextures/Blurred Spec 11 (stretched along the crack = glow band)
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
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

-- Value of a keyframe track { {time, value}, ... } at t, smoothstepped between keys
-- and held at both ends.
local function track(keys, t)
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b[1] then
			local alpha = (t - a[1]) / math.max(b[1] - a[1], 1e-6)
			alpha = alpha * alpha * (3 - 2 * alpha)
			return a[2] + (b[2] - a[2]) * alpha
		end
	end
	return keys[#keys][2]
end

-- Ground point below ctx.CFrame, skipping characters (same as FireballExplosion).
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

local function attachment(parent, cframe)
	local att = Instance.new("Attachment")
	att.CFrame = cframe
	att.Parent = parent
	return att
end

-- Beam (camera-facing unless props say otherwise) from `top` down to `bottom` (a beam draws its texture's top at
-- Attachment0, so flames point up).
local function beam(top, bottom, props)
	local b = Instance.new("Beam")
	b.Attachment0 = top
	b.Attachment1 = bottom
	b.FaceCamera = true
	b.LightInfluence = 0
	b.Segments = 1
	b.TextureMode = Enum.TextureMode.Stretch
	b.TextureLength = 1
	b.Width0 = 0
	b.Width1 = 0
	for key, value in props do
		b[key] = value
	end
	b.Parent = top.Parent
	return b
end

--------------------------------------------------------------------------------

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(255, 120, 30), -- dominant flame orange
	CoreColor = Color3.fromRGB(255, 200, 80), -- yellow core, low in the middle
	EdgeColor = Color3.fromRGB(200, 45, 15), -- deep red tongue edges and crack lava
	DarkColor = Color3.fromRGB(22, 14, 12), -- crack, dark streaks, flecks, dark tongues
	SmokeColor = Color3.fromRGB(40, 40, 48), -- darker than the sky
	RockColor = Color3.fromRGB(45, 40, 40), -- near-black shards
	WindColor = Color3.fromRGB(255, 150, 105), -- peach wind arcs (fading to red)
	Scale = 3, -- 3x the original size (fissure ~60 studs long)
	WallLength = 20, -- fissure length (studs); every other size follows it
	-- timing: keep EruptTime >= 0.5 and FadeTime >= 0.7 (the precursor and die-down keys
	-- are laid out inside those windows)
	EruptTime = 0.69, -- crack -> eruption (spike row; the curtain is up ~0.04 s later)
	BurnTime = 2.3, -- eruption -> the curtain starts to narrow
	FadeTime = 0.67, -- narrowing to a thin bundle and going out (abruptly at the end)
	CrackFadeTime = 0.7, -- the crack's glow after the flames are gone
	FlameRate = 64, -- flame tongues / s while burning
	EmberRate = 10, -- embers / s while burning
	CurlRate = 8, -- orange curls and ring curls / s
	FleckRate = 9, -- dark flecks / s
	DarkTongueRate = 6, -- dark charcoal tongues / s at the curtain's sides
	RockCount = 8,
	LightBrightness = 1.2,
	LightRange = 16,
}

Effect.Linger = 1

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local F = p.WallLength * s -- crack length: the glowing line runs the full F
	-- body size: the curtain, precursor, wind and smoke cover the middle ~half of the crack
	-- (measured from two camera angles: curtain ~0.5 F wide and ~0.5 F tall)
	local B = 0.72 * F
	local H = 0.65 * B -- curtain (veil) height; the centre band reaches ~0.95 B

	local ground = findGround(ctx)
	local look = ctx.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	-- facing away from the viewer, like a camera: X = viewer's right, +Z = toward viewer
	local frame = CFrame.lookAt(ground, ground - look.Unit)

	-- Box emitters (particles spawn anywhere in the part). Flame quads are centred on the
	-- particle with the flame's base low in the cell, so flame boxes sit higher to keep the
	-- ground from slicing them with a hard straight edge.
	local function box(x, y, width)
		local part = ctx.Anchor(frame * CFrame.new(x, y, 0))
		part.Size = Vector3.new(width, 0.2 * s, 1 * s)
		return part
	end
	local line = box(0, 0.6 * s, 0.75 * B) -- along the middle of the fissure (~±5.4 studs)
	-- moved between the precursor streak clusters, then between the curtain's edges for
	-- the dark side tongues
	local burstBox = box(0, 0.6 * s, 0.22 * B)
	local midFlames = box(0, 0.07 * B, 0.6 * B) -- precursor flames, rocks, smoke: middle of the crack
	local tallLeft = box(-0.25 * B, 0.24 * B, 0.5 * B) -- tongue halves; widths follow the curtain
	local tallRight = box(0.25 * B, 0.24 * B, 0.5 * B)
	local tallCentre = box(0, 0.27 * B, 0.3 * B) -- taller tongues and the flame body, middle of the curtain

	local base = ctx.Anchor(frame)
	local centre = attachment(base, CFrame.new(0, 0.4 * s, 0))
	-- wind arcs: flat on the ground, and raised + tilted so some wrap up round the flames
	local windLow = centre
	local windHigh = attachment(base, CFrame.new(0, 0.35 * B, 0) * CFrame.Angles(math.rad(-20), 0, math.rad(8)))

	------------------------------------------------------------------ crack decal
	-- The rift on the ground: a dark jagged crack, a thin hot line along it and a faint red
	-- pool round it, heating up before the eruption. SurfaceGuis with LightInfluence 0
	-- so Brightness glows. A Top-face SurfaceGui runs the image's X along the part's Z, so
	-- each part is turned to lay the rift along the fissure.
	local function crackLayer(name, depth, length, image, color, lift)
		-- each layer a little higher than the last so they don't z-fight
		local part = ctx.Anchor(frame * CFrame.new(0, (0.04 + lift) * s, 0) * CFrame.Angles(0, math.pi / 2, 0))
		part.Size = Vector3.new(depth, 0.05, length)
		local gui = Instance.new("SurfaceGui")
		gui.Name = name
		gui.Face = Enum.NormalId.Top
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		local label = Instance.new("ImageLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Image = image
		label.ImageColor3 = color
		label.ImageTransparency = 1
		label.Parent = gui
		gui.Parent = part
		return gui, label
	end
	local _, crackDark = crackLayer("CrackDark", 4 * s, F * 0.62, ASSETS.BranchCrack, p.DarkColor, 0)
	-- lumpy lava in the middle of the crack (the rift texture, bright orange) and a soft red
	-- pool round it; the hot line beam below covers the whole crack once it erupts
	local lineGui, crackLine = crackLayer("CrackLine", 4 * s, F * 0.36, ASSETS.Rift, p.Color, 0.02)
	local poolGui, crackPool = crackLayer("CrackPool", 3 * s, F * 0.45, ASSETS.SoftGlow, p.EdgeColor, 0.01)

	------------------------------------------------------------------ precursor emitters
	local streakOrange = emitter(burstBox, {
		Texture = ASSETS.FlameStreak,
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		EmissionDirection = Enum.NormalId.Top,
		Color = colors({ { 0, p.Color }, { 1, p.EdgeColor } }),
		LightEmission = 0.6,
		Brightness = 1,
		Size = seq({ { 0, 1.7 * s, 0.4 * s }, { 1, 1.3 * s } }),
		Squash = NumberSequence.new(0.6),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.2 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.035, 0.055),
		Speed = NumberRange.new(6 * s, 14 * s),
		SpreadAngle = Vector2.new(6, 6),
		ZOffset = 1,
	})
	local streakDark = emitter(burstBox, {
		Texture = ASSETS.FlameStreak,
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(p.DarkColor),
		LightEmission = 0,
		Size = seq({ { 0, 1.8 * s, 0.4 * s }, { 1, 1.4 * s } }),
		Squash = NumberSequence.new(0.8),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.04, 0.06),
		Speed = NumberRange.new(4 * s, 9 * s),
		SpreadAngle = Vector2.new(8, 8),
		ZOffset = 1.2,
	})
	local rocks = emitter(midFlames, {
		Texture = ASSETS.Rocks,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.Loop,
		FlipbookFramerate = NumberRange.new(0),
		FlipbookStartRandom = true,
		EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(p.RockColor),
		LightEmission = 0,
		Size = seq({ { 0, 1.1 * s, 0.3 * s }, { 0.8, 1 * s }, { 1, 0 } }),
		Squash = NumberSequence.new(0.9), -- tall thin shards
		Lifetime = NumberRange.new(0.2, 0.3),
		Speed = NumberRange.new(12 * s, 20 * s),
		SpreadAngle = Vector2.new(18, 18),
		Acceleration = Vector3.new(0, -60 * s, 0),
		Drag = 3,
		Rotation = NumberRange.new(-25, 25),
		RotSpeed = NumberRange.new(-90, 90),
		ZOffset = 0.5,
	})
	local preFlames = emitter(midFlames, {
		Texture = ASSETS.FlamePillar,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.Loop, -- first frames are tiny: random start
		FlipbookFramerate = NumberRange.new(18, 24),
		FlipbookStartRandom = true,
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		EmissionDirection = Enum.NormalId.Top,
		Color = colors({ { 0, p.Color }, { 0.6, p.EdgeColor }, { 1, p.EdgeColor } }),
		LightEmission = 0.8,
		Brightness = 1.2,
		Size = seq({ { 0, 1.3 * s }, { 0.4, 1.8 * s, 0.3 * s }, { 1, 1.6 * s } }),
		Squash = NumberSequence.new(0.4),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.14, 0.2),
		Speed = NumberRange.new(1 * s, 2 * s),
		Rotation = NumberRange.new(-8, 8),
		ZOffset = 1,
	})
	local ringCurls = emitter(line, {
		Texture = ASSETS.RingCurl,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		EmissionDirection = Enum.NormalId.Top,
		Color = colors({ { 0, p.Color }, { 1, p.EdgeColor } }),
		LightEmission = 1,
		Brightness = 1.4,
		Size = seq({ { 0, 0.9 * s, 0.2 * s }, { 1, 1.1 * s } }),
		Lifetime = NumberRange.new(0.45, 0.75),
		Speed = NumberRange.new(8 * s, 16 * s),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, -4 * s, 0),
		Drag = 4,
		Rotation = NumberRange.new(0, 360),
		ZOffset = 1.5,
	})
	-- dark smoke: columnar plumes over the middle 0.8 B that shoot up, top out ~0.7-0.85 B
	-- by 0.2-0.3 s under heavy drag and are gone by ~0.4 s (measured). Spawned in three
	-- waves to 0.15 s so the plumes stay attached to the ground.
	local smoke = emitter(midFlames, {
		Texture = ASSETS.SoftSmoke,
		EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(p.SmokeColor),
		LightEmission = 0,
		Size = seq({ { 0, 2.6 * s }, { 1, 5.2 * s, 1.1 * s } }),
		Transparency = seq({ { 0, 0.45 }, { 0.5, 0.55 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.24, 0.3),
		Speed = NumberRange.new(55 * s, 75 * s),
		SpreadAngle = Vector2.new(10, 10),
		Drag = 12,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		ZOffset = -1,
	})
	local embers = emitter(line, {
		Texture = ASSETS.Speck,
		EmissionDirection = Enum.NormalId.Top,
		Color = colors({ { 0, p.Color }, { 1, p.EdgeColor } }),
		LightEmission = 1,
		Brightness = 1.5,
		Size = seq({ { 0, 0.35 * s, 0.1 * s }, { 0.8, 0.3 * s }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(6 * s, 16 * s),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(2 * s, -6 * s, 0),
		Drag = 1.2,
		ZOffset = 2,
	})

	------------------------------------------------------------------ eruption emitters
	local spikes = emitter(line, {
		Texture = ASSETS.FlameStreak,
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		EmissionDirection = Enum.NormalId.Top,
		Color = colors({ { 0, p.CoreColor }, { 1, p.Color } }),
		LightEmission = 1,
		Brightness = 1.8,
		Size = seq({ { 0, 1.5 * s, 0.4 * s }, { 1, 1.8 * s } }),
		Squash = NumberSequence.new(0.8),
		Transparency = seq({ { 0, 0 }, { 0.7, 0 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.035, 0.055),
		Speed = NumberRange.new(10 * s, 20 * s),
		ZOffset = 2,
	})
	-- smooth thin upright tongues; each half leans a little inward so the curtain stays
	-- tight, and the centre band is ~1.3x taller so the silhouette tapers. They shoot up
	-- fast (TONGUE_RUSH) and die young, so the curtain rushes; WALL_HEIGHT trims the
	-- tongues, flame body and the veil/column beams to ~0.85 of the original height.
	local TONGUE_RUSH = 1.6
	local WALL_HEIGHT = 0.85
	local tongueLifeK = WALL_HEIGHT / TONGUE_RUSH
	local function tongueEmitter(anchor, inward, height)
		return emitter(anchor, {
			Texture = ASSETS.FireTower,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
			FlipbookMode = Enum.ParticleFlipbookMode.Loop, -- random start: no tiny first frames
			FlipbookFramerate = NumberRange.new(24, 32),
			FlipbookStartRandom = true,
			Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
			EmissionDirection = Enum.NormalId.Top,
			Color = colors({ { 0, p.Color }, { 0.4, p.Color }, { 0.6, p.EdgeColor }, { 1, p.EdgeColor } }),
			LightEmission = 0.75,
			Brightness = 1,
			Size = seq({ { 0, 0.21 * B * height, 0.03 * B }, { 0.5, 0.26 * B * height, 0.03 * B }, { 1, 0.24 * B * height } }),
			Squash = seq({ { 0, 0.5 }, { 1, 0.8 } }),
			Transparency = seq({ { 0, 0.1 }, { 0.5, 0.3 }, { 0.6, 0.45 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.35 * tongueLifeK, 0.55 * tongueLifeK),
			Speed = NumberRange.new(0.44 * B * height * TONGUE_RUSH, 0.74 * B * height * TONGUE_RUSH),
			Drag = 1.5,
			SpreadAngle = Vector2.new(4, 4),
			-- positive Rotation turns counter-clockwise on screen (tops lean left)
			Rotation = NumberRange.new(math.min(0, inward * 5), math.max(0, inward * 5)),
			ZOffset = 1,
		})
	end
	local tonguesLeft = tongueEmitter(tallLeft, -1, 1) -- left half leans right (inward)
	local tonguesRight = tongueEmitter(tallRight, 1, 1)
	local tonguesCentre = tongueEmitter(tallCentre, 0, 1.3)
	local function setTongueSpeed(k)
		k *= TONGUE_RUSH
		tonguesLeft.Speed = NumberRange.new(0.44 * B * k, 0.74 * B * k)
		tonguesRight.Speed = tonguesLeft.Speed
		tonguesCentre.Speed = NumberRange.new(0.44 * B * 1.3 * k, 0.74 * B * 1.3 * k)
	end
	local function centreSizeAt(k)
		local h = 1.3 * k
		return seq({ { 0, 0.21 * B * h, 0.03 * B }, { 0.5, 0.26 * B * h, 0.03 * B }, { 1, 0.24 * B * h } })
	end
	local lastCentreSize = 1
	-- soft flame body filling the middle of the curtain up to ~0.85 of its height
	local flameBody = emitter(tallCentre, {
		Texture = ASSETS.FlameBody,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.Loop,
		FlipbookFramerate = NumberRange.new(14, 18),
		FlipbookStartRandom = true,
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		EmissionDirection = Enum.NormalId.Top,
		Color = colors({ { 0, p.CoreColor }, { 0.35, p.Color }, { 1, p.EdgeColor } }),
		LightEmission = 0.6,
		Brightness = 1,
		Size = seq({ { 0, 0.18 * B }, { 0.5, 0.22 * B, 0.03 * B }, { 1, 0.2 * B } }),
		Squash = NumberSequence.new(1), -- ~2:1 upright, so it never reads as round balls
		Transparency = seq({ { 0, 0.4 }, { 0.4, 0.55 }, { 0.7, 0.75 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.4 * tongueLifeK, 0.6 * tongueLifeK),
		Speed = NumberRange.new(0.25 * B * TONGUE_RUSH, 0.43 * B * TONGUE_RUSH),
		Drag = 1.5,
		SpreadAngle = Vector2.new(6, 6),
		ZOffset = 0.8,
	})
	local function darkTongueEmitter(anchor)
		return emitter(anchor, {
			Texture = ASSETS.FlamePillar,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
			FlipbookMode = Enum.ParticleFlipbookMode.Loop,
			FlipbookFramerate = NumberRange.new(14, 18),
			FlipbookStartRandom = true,
			Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
			EmissionDirection = Enum.NormalId.Top,
			Color = ColorSequence.new(p.DarkColor),
			LightEmission = 0,
			Size = seq({ { 0, 0.12 * B }, { 0.5, 0.16 * B }, { 1, 0.14 * B } }),
			Squash = NumberSequence.new(0.5),
			Transparency = seq({ { 0, 0.05 }, { 0.6, 0.2 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.3, 0.45),
			Speed = NumberRange.new(0.15 * B, 0.3 * B),
			Rotation = NumberRange.new(-15, 15),
			Drag = 1.5,
			ZOffset = 1.5,
		})
	end
	local darkTongues = darkTongueEmitter(burstBox)
	local curls = emitter(line, {
		Texture = ASSETS.FlameWisp,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		EmissionDirection = Enum.NormalId.Top,
		Color = colors({ { 0, p.CoreColor }, { 0.4, p.Color }, { 1, p.EdgeColor } }),
		LightEmission = 0.8,
		Brightness = 1.5,
		Size = seq({ { 0, 0.8 * s }, { 0.5, 1.6 * s, 0.4 * s }, { 1, 1.4 * s } }),
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(5 * s, 12 * s),
		SpreadAngle = Vector2.new(50, 50),
		Acceleration = Vector3.new(0, -10 * s, 0),
		Rotation = NumberRange.new(-40, 40),
		ZOffset = 2,
	})
	local flecks = emitter(line, {
		Texture = ASSETS.FlameWisp,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(p.DarkColor),
		LightEmission = 0,
		Size = seq({ { 0, 0.6 * s }, { 0.5, 1.1 * s, 0.3 * s }, { 1, 0.9 * s } }),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(4 * s, 10 * s),
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, -12 * s, 0),
		Rotation = NumberRange.new(-30, 30),
		ZOffset = 2.5,
	})
	-- wind: a swirl of arcs round the base, a little longer along the fissure (~1.3:1; on a
	-- ground-flat particle a negative Squash stretches it along the attachment's X), flat
	-- on the ground and raised + tilted so some wrap up round the flames. Each arc rises
	-- ~0.3 B (~13 studs at Scale 3) as it spins out; VelocityPerpendicular keeps it flat
	-- while it moves up.
	local windHalf = 0.31 * B -- arcs reach ~7 studs out along the fissure, ~5.5 across
	local function windEmitter(att, sizeScale)
		return emitter(att, {
			Texture = ASSETS.Swirl,
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			EmissionDirection = Enum.NormalId.Top,
			Color = colors({ { 0, p.WindColor }, { 1, p.EdgeColor } }),
			LightEmission = 0.6,
			Brightness = 1.1,
			Size = seq({ { 0, windHalf * 1.25 * sizeScale }, { 0.5, windHalf * 1.55 * sizeScale }, { 1, windHalf * 1.7 * sizeScale } }),
			Squash = NumberSequence.new(-0.45),
			Transparency = seq({ { 0, 0.4 }, { 0.55, 0.52 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.42, 0.5),
			Speed = NumberRange.new(1 * B, 1.2 * B),
			Drag = 2.5,
			Rotation = NumberRange.new(-10, 10),
			RotSpeed = NumberRange.new(30, 60),
		})
	end
	local windGround = windEmitter(windLow, 1)
	local windTilt = windEmitter(windHigh, 0.75)
	-- base splash at the onset: short bright streaks radiating out low from the fissure
	-- (VelocityParallel quads smear along their motion, which is the look here)
	local splash = emitter(line, {
		Texture = ASSETS.FlameStreak,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		EmissionDirection = Enum.NormalId.Front, -- across the fissure, fanned all round flat
		Color = colors({ { 0, p.CoreColor }, { 1, p.Color } }),
		LightEmission = 1,
		Brightness = 1.8,
		Size = seq({ { 0, 1.2 * s }, { 1, 1.8 * s } }),
		Squash = NumberSequence.new(0.6),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.2 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.05, 0.08),
		Speed = NumberRange.new(35 * s, 55 * s),
		SpreadAngle = Vector2.new(180, 12),
		Acceleration = Vector3.new(0, 20 * s, 0),
		ZOffset = 3,
	})

	------------------------------------------------------------------ beams
	-- Faint veil of tongues behind the particles (two scrolling sheets), the central
	-- tapered flame with a soft glow, and a faint dim red streak above it (all fixed, not
	-- camera-facing).
	-- The veil and the central flame are fixed sheets (FaceCamera off) that lie along the
	-- fissure: a non-camera-facing beam spreads its width along its attachments' Y axis, so
	-- these attachments turn X up the flame, Y along the fissure and Z toward the viewer's
	-- side.
	local upright = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.xAxis)
	local bottom = attachment(base, CFrame.new(0, 0.2 * s, 0) * upright)
	local wallTop = attachment(base, CFrame.new(0, 0.2 * s, 0) * upright)
	local columnBottom = attachment(base, CFrame.new(0, 0.2 * s, 0) * upright)
	local columnTop = attachment(base, CFrame.new(0, 0.2 * s, 0) * upright)
	local streakTop = attachment(base, CFrame.new(0, 0.2 * s, 0) * upright)
	local coreTop = attachment(base, CFrame.new(0, 0.2 * s, 0) * upright)
	local veil = seq({ { 0, 1 }, { 0.55, 0.8 }, { 0.85, 0.5 }, { 1, 0.55 } })
	local wisps = beam(wallTop, bottom, {
		Name = "WallWisps",
		FaceCamera = false,
		Texture = ASSETS.FlameWisps,
		Color = colors({ { 0, p.EdgeColor }, { 0.5, p.Color }, { 1, p.CoreColor } }),
		LightEmission = 1,
		Brightness = 0.7,
		Transparency = veil,
		TextureSpeed = 0.9 * ctx.TimeScale,
		ZOffset = -0.5,
	})
	local peaks = beam(wallTop, bottom, {
		Name = "WallPeaks",
		FaceCamera = false,
		Texture = ASSETS.FlamePeaks,
		Color = colors({ { 0, p.EdgeColor }, { 0.6, p.Color }, { 1, p.CoreColor } }),
		LightEmission = 1,
		Brightness = 0.5,
		Transparency = veil,
		TextureSpeed = 0.6 * ctx.TimeScale,
		ZOffset = -0.4,
	})
	local column = beam(columnTop, columnBottom, {
		Name = "Column",
		FaceCamera = false,
		Texture = ASSETS.FireColumn,
		Color = colors({ { 0, p.EdgeColor }, { 0.5, p.Color }, { 1, p.CoreColor } }),
		LightEmission = 1,
		Brightness = 1.1,
		Transparency = seq({ { 0, 1 }, { 0.3, 0.35 }, { 0.6, 0.05 }, { 1, 0 } }),
		TextureSpeed = 1.4 * ctx.TimeScale,
		ZOffset = 0.5,
	})
	local columnGlow = beam(columnTop, columnBottom, {
		Name = "ColumnGlow",
		FaceCamera = false,
		Texture = ASSETS.GlowCore,
		Color = ColorSequence.new(p.Color),
		LightEmission = 1,
		Brightness = 1,
		Transparency = seq({ { 0, 1 }, { 0.5, 0.7 }, { 1, 0.55 } }),
		ZOffset = -0.6,
	})
	-- bright yellow interior over the column's lower half
	local core = beam(coreTop, columnBottom, {
		Name = "Core",
		FaceCamera = false,
		Texture = ASSETS.GlowCore,
		Color = ColorSequence.new(p.CoreColor),
		LightEmission = 1,
		Brightness = 1.4,
		Transparency = seq({ { 0, 1 }, { 0.4, 0.4 }, { 1, 0.15 } }),
		ZOffset = 0.6,
	})
	local streak = beam(streakTop, columnTop, {
		Name = "Streak",
		FaceCamera = false,
		Texture = ASSETS.GlowCore,
		Color = ColorSequence.new(p.EdgeColor),
		LightEmission = 1,
		Brightness = 1,
		Transparency = seq({ { 0, 1 }, { 0.5, 0.75 }, { 1, 0.7 } }),
		ZOffset = 0.4,
	})

	-- hot line along the whole crack: a thin camera-facing ribbon between the crack's ends
	local lineLeft = attachment(base, CFrame.new(-F * 0.5, 0.12 * s, 0))
	local lineRight = attachment(base, CFrame.new(F * 0.5, 0.12 * s, 0))
	local hotLine = beam(lineLeft, lineRight, {
		Name = "HotLine",
		Texture = ASSETS.GlowCore,
		Color = ColorSequence.new(p.Color),
		LightEmission = 1,
		Brightness = 6,
		Width0 = 0.9 * s,
		Width1 = 0.9 * s,
		Transparency = NumberSequence.new(1),
		ZOffset = 3,
	})

	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = math.min(p.LightRange * s, 20) -- budget: Range 20 or less
	light.Brightness = 0
	light.Shadows = false
	light.Parent = midFlames -- low in the middle of the fissure

	------------------------------------------------------------------ timeline
	local E = p.EruptTime
	local burnEnd = E + p.BurnTime
	local fadeEnd = burnEnd + p.FadeTime
	local crackEnd = fadeEnd + p.CrackFadeTime
	local narrowEnd = burnEnd + p.FadeTime * 0.85 -- the curtain is a thin bundle from here

	local function streakCluster(x)
		return function()
			burstBox.CFrame = frame * CFrame.new(x, 0.6 * s, 0)
			ctx.Emit(streakOrange, 7)
			ctx.Emit(streakDark, 5)
		end
	end

	-- one-off bursts, at most one per loop step (a box moved between emits in the same
	-- frame would spawn every burst at its last position)
	local bursts = {
		{ 0.04, streakCluster(-0.28 * B) },
		{ 0.044, streakCluster(0.02 * B) },
		{ 0.048, streakCluster(0.3 * B) },
		{ 0.055, function()
			ctx.Emit(rocks, p.RockCount)
			ctx.Emit(ringCurls, 4)
			ctx.Emit(preFlames, 5)
		end },
		{ 0.075, function()
			ctx.Emit(smoke, 9)
			ctx.Emit(embers, 2)
		end },
		{ 0.11, function()
			ctx.Emit(preFlames, 6)
			ctx.Emit(smoke, 8)
		end },
		{ 0.15, function()
			ctx.Emit(smoke, 5)
		end },
		{ 0.17, function()
			ctx.Emit(preFlames, 6)
		end },
		{ 0.23, function()
			ctx.Emit(preFlames, 5)
		end },
		{ 0.28, function()
			ctx.Emit(preFlames, 4)
		end },
		{ E - 0.03, function()
			setTongueSpeed(1.8) -- the first tongues shoot up so the wall is up by E + 0.06
			-- re-centre the burst box over the middle 0.8 B for the onset's dark streaks
			burstBox.CFrame = frame * CFrame.new(0, 0.6 * s, 0)
			burstBox.Size = Vector3.new(0.8 * B, 0.2 * s, 1 * s)
		end },
		{ E, function()
			ctx.Emit(spikes, 24)
			ctx.Emit(streakDark, 8)
		end },
		{ E + 0.012, function()
			ctx.Emit(splash, 18)
			ctx.Emit(tonguesLeft, 7)
			ctx.Emit(tonguesRight, 7)
			ctx.Emit(tonguesCentre, 6)
		end },
		{ E + 0.02, function()
			ctx.Emit(windGround, 3)
		end },
		{ E + 0.1, function()
			setTongueSpeed(1)
		end },
		{ E + 0.09, function()
			ctx.Emit(windTilt, 2)
			ctx.Emit(curls, 8)
			ctx.Emit(flecks, 6)
		end },
		{ E + 0.14, function()
			ctx.Emit(windTilt, 1)
			ctx.Emit(windGround, 2)
		end },
		{ E + 0.22, function()
			ctx.Emit(windTilt, 2)
			ctx.Emit(windGround, 1)
			-- now the dark side tongue spot, starting at the curtain's right edge
			burstBox.Size = Vector3.new(0.08 * B, 0.2 * s, 1 * s)
			burstBox.CFrame = frame * CFrame.new(0.36 * B, 0.12 * B, 0)
		end },
	}
	local nextBurst = 1
	local darkSide = 1

	-- channel rates over time (per second)
	-- emission stops ~0.15 s before fadeEnd and the tongue lifetime shrinks, so the last
	-- ones are gone right at fadeEnd
	local burning = { { E + 0.03, 0 }, { E + 0.08, 1 }, { narrowEnd - 0.05, 1 }, { fadeEnd - 0.08, 0 } }
	local tongueLife = { { burnEnd + 0.3, 1 }, { fadeEnd - 0.1, 0.25 } }
	local edgeLife = { { burnEnd, 1 }, { burnEnd + 0.1, 0.4 } } -- no tall edge strays after ~3 s
	local centreGlow = { { burnEnd, 1 }, { burnEnd + 0.2, 1.3 } } -- brighter bundle in the die-down
	local centreSize = { { burnEnd, 1 }, { burnEnd + 0.3, 0.75 }, { burnEnd + 0.55, 0.5 } }
	local edgeBurning = { { E + 0.03, 0 }, { E + 0.08, 1 }, { burnEnd, 1 }, { burnEnd + 0.1, 0 } }
	-- the reference opens into a V twice: a bright central column with sparse tongues leaning
	-- 20-30 deg outward (~1.0 s), and again as it dies (an inverted cone at ~3.3 s)
	local vLean = { { E + 0.2, 0 }, { E + 0.26, 1 }, { E + 0.36, 1 }, { E + 0.45, 0 },
		{ burnEnd - 0.12, 0 }, { burnEnd - 0.06, 1 }, { burnEnd + 0.4, 1 }, { burnEnd + 0.5, 0 } }
	local channels = {
		{ tonguesLeft, p.FlameRate * 0.35, edgeBurning, vThin = true },
		{ tonguesRight, p.FlameRate * 0.35, edgeBurning, vThin = true },
		{ tonguesCentre, p.FlameRate * 0.3, burning },
		{ flameBody, p.FlameRate * 0.25, { { E + 0.12, 0 }, { E + 0.18, 1 }, { burnEnd + 0.3, 1 }, { burnEnd + 0.5, 0 } } },
		{ darkTongues, p.DarkTongueRate, { { E + 0.3, 0 }, { E + 0.4, 1 }, { burnEnd, 1 }, { burnEnd + 0.2, 0 } } },
		{ embers, p.EmberRate, { { E, 0 }, { E + 0.1, 1 }, { burnEnd, 1 }, { burnEnd + 0.3, 0.2 }, { fadeEnd - 0.1, 0 } } },
		{ curls, p.CurlRate, { { E + 0.1, 0 }, { E + 0.15, 1 }, { burnEnd - 0.2, 1 }, { burnEnd, 0 } } },
		{ ringCurls, p.CurlRate * 0.6, { { E + 0.1, 0 }, { E + 0.15, 1 }, { burnEnd - 0.3, 1 }, { burnEnd, 0 } } },
		{ flecks, p.FleckRate, { { E + 0.1, 0 }, { E + 0.15, 1 }, { burnEnd - 0.1, 1 }, { burnEnd + 0.1, 0 } } },
	}
	local owed = {}
	for i = 1, #channels do
		owed[i] = 0
	end

	-- curtain width (tongue box width, fraction of B; the quads add ~1.5 studs a side): ~13
	-- studs across at the onset, ~11 while burning, then narrowing to a ~1 stud bundle at 3.6 s
	local curtain = {
		{ E, 0.6 }, { E + 0.03, 0.7 }, { E + 0.3, 0.6 }, { burnEnd, 0.6 },
		{ burnEnd + 0.15, 0.35 }, { burnEnd + 0.3, 0.2 }, { burnEnd + 0.45, 0.08 }, { fadeEnd, 0.03 },
	}
	-- the veil overshoots a little at the onset (the reference's first wall is tallest)
	local wallH = H * WALL_HEIGHT
	local wallHeight = { { E, 0 }, { E + 0.035, wallH * 1.15 }, { E + 0.35, wallH }, { narrowEnd, wallH }, { fadeEnd, wallH * 0.85 } }
	local wallAlpha = { { E, 0 }, { E + 0.02, 1 }, { narrowEnd - 0.1, 1 }, { fadeEnd - 0.05, 0 } }
	local colH = B * WALL_HEIGHT
	local columnHeight = { { E + 0.12, 0 }, { E + 0.24, 0.75 * colH }, { narrowEnd, 0.75 * colH }, { fadeEnd, 0.7 * colH } }
	local columnWidth = {
		{ E + 0.12, 0 }, { E + 0.24, 0.32 * B }, { burnEnd, 0.32 * B }, { narrowEnd, 0.12 * B }, { fadeEnd, 0 },
	}
	local streakHeight = { { E + 0.3, 0.72 * colH }, { E + 0.45, 0.9 * colH }, { burnEnd, 0.9 * colH }, { fadeEnd, 0.6 * colH } }
	-- side-to-side sway of the whole curtain: a sideways push on the live tongues and body
	-- (they bend together) and the beam tops swinging the same way
	local swayAmount = { { E + 0.1, 0 }, { E + 0.35, 1 }, { burnEnd + 0.2, 1 }, { fadeEnd, 0.3 } }
	local swayRight = frame.RightVector
	local swayed = { tonguesLeft, tonguesRight, tonguesCentre, flameBody }
	local lightTrack = { { E, 0 }, { E + 0.05, p.LightBrightness * 1.5 }, { E + 0.3, p.LightBrightness },
		{ burnEnd, p.LightBrightness }, { fadeEnd, 0 } }
	local lineTrack = { { E + 0.012, 1 }, { E + 0.08, 0 }, { narrowEnd, 0 }, { fadeEnd + 0.2, 1 } }
	-- the dark rift recedes while the hot line burns along it
	local crackDarkTrack = { { 0.03, 1 }, { 0.09, 0.15 }, { E, 0.15 }, { E + 0.1, 0.55 }, { fadeEnd, 0.4 },
		{ crackEnd - 0.3, 0.3 }, { crackEnd, 1 } }
	local crackLineTrack = { { 0.3, 1 }, { 0.5, 0.1 }, { E, 0 }, { fadeEnd, 0.15 }, { crackEnd, 1 } }
	-- the pool is a soft glow stretched along the crack: brightest in the middle
	local crackPoolTrack = { { 0.3, 1 }, { 0.5, 0.45 }, { E, 0.4 }, { E + 0.2, 0.7 }, { fadeEnd, 0.8 }, { crackEnd, 1 } }
	local crackBrightTrack = { { 0.3, 1 }, { 0.6, 2.6 }, { E + 0.1, 3.2 }, { fadeEnd, 2 }, { crackEnd, 0.8 } }

	local t = 0
	while t < crackEnd do
		local burst = bursts[nextBurst]
		if burst and t >= burst[1] then
			burst[2]()
			nextBurst += 1
		end

		local dt = ctx.Wait(1 / 240) -- every rendered frame, so the ~30 ms pops hold up in slow-mo
		t += dt

		for i, channel in channels do
			local rate = channel[2] * track(channel[3], t)
			if channel.vThin then
				rate *= 1 - 0.55 * track(vLean, t)
			end
			owed[i] += rate * dt
			local n = math.floor(owed[i])
			if n > 0 then
				owed[i] -= n
				ctx.Emit(channel[1], n)
				if channel[1] == darkTongues then
					-- next dark tongue on the other edge (moving the box after emitting, so it
					-- takes effect from the next step)
					darkSide = -darkSide
					burstBox.CFrame = frame * CFrame.new(darkSide * track(curtain, t) * B * 0.48, 0.12 * B, 0)
				end
			end
		end

		local life = track(tongueLife, t)
		local edge = math.min(life, track(edgeLife, t)) * tongueLifeK
		life *= tongueLifeK
		tonguesLeft.Lifetime = NumberRange.new(0.35 * edge, 0.55 * edge)
		tonguesRight.Lifetime = tonguesLeft.Lifetime
		tonguesCentre.Lifetime = NumberRange.new(0.35 * life, 0.55 * life)
		tonguesCentre.Brightness = track(centreGlow, t)
		local lean = track(vLean, t)
		-- positive Rotation leans tops left: the left half leans in by default, out in a V
		tonguesLeft.Rotation = NumberRange.new(-5 + 25 * lean, 32 * lean)
		tonguesRight.Rotation = NumberRange.new(-32 * lean, 5 - 25 * lean)
		tonguesCentre.Rotation = NumberRange.new(-14 * lean, 14 * lean)
		core.Brightness = 1.4 + 1.2 * lean
		local cs = track(centreSize, t)
		if cs ~= lastCentreSize then
			lastCentreSize = cs
			tonguesCentre.Size = centreSizeAt(cs)
		end

		-- curtain: the tongue boxes and the veil follow its width
		local width = track(curtain, t) * B
		tallLeft.Size = Vector3.new(width / 2, 0.2 * s, 1 * s)
		tallRight.Size = tallLeft.Size
		tallLeft.CFrame = frame * CFrame.new(-width / 4, 0.24 * B, 0)
		tallRight.CFrame = frame * CFrame.new(width / 4, 0.24 * B, 0)
		tallCentre.Size = Vector3.new(width * 0.6, 0.2 * s, 1 * s) -- body ~0.85 B wide with its quads
		local veilWidth = width * 1.05 * track(wallAlpha, t)
		wisps.Width0, wisps.Width1 = veilWidth * 0.7, veilWidth
		peaks.Width0, peaks.Width1 = veilWidth * 0.55, veilWidth * 0.9
		-- two mixed sines (~0.9 and ~1.6 sways/s) so the swing never looks mechanical
		local sway = track(swayAmount, t) * (0.75 * math.sin(t * 5.7) + 0.25 * math.sin(t * 10.1 + 1.3))
		local push = swayRight * (1.6 * B * sway)
		for _, e in swayed do
			e.Acceleration = push
		end
		local swayX = 0.07 * B * sway
		wallTop.Position = Vector3.new(swayX, 0.2 * s + track(wallHeight, t), 0)

		local columnTopY = 0.2 * s + track(columnHeight, t)
		columnTop.Position = Vector3.new(swayX, columnTopY, 0)
		streakTop.Position = Vector3.new(swayX * 1.2, math.max(columnTopY, 0.2 * s + track(streakHeight, t)), 0)
		local cw = track(columnWidth, t)
		column.Width0, column.Width1 = cw * 0.05, cw -- pointed tip, wide base
		columnGlow.Width0, columnGlow.Width1 = cw * 0.5, cw * 1.8
		streak.Width0, streak.Width1 = cw * 0.04, cw * 0.1
		coreTop.Position = Vector3.new(swayX * 0.75, 0.2 * s + (columnTopY - 0.2 * s) * 0.75, 0)
		core.Width0, core.Width1 = cw * 0.25, cw * 0.6

		light.Brightness = track(lightTrack, t)
		local lineAlpha = track(lineTrack, t)
		hotLine.Transparency = seq({ { 0, 1 }, { 0.12, lineAlpha }, { 0.88, lineAlpha }, { 1, 1 } })
		crackDark.ImageTransparency = track(crackDarkTrack, t)
		crackLine.ImageTransparency = track(crackLineTrack, t)
		crackPool.ImageTransparency = track(crackPoolTrack, t)
		lineGui.Brightness = track(crackBrightTrack, t)
		poolGui.Brightness = track(crackBrightTrack, t) * 0.7
	end
end

return Effect
