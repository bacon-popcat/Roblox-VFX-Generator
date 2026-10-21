-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/LavaEruption
-- A lava fissure. Anticipation: the crack splits the ground with streaks, flung rocks,
-- small flames, ring curls and a grey smoke veil that shoots up, and heats to red. Then a
-- spiky flash runs along it, a spike row and a splash fire, and a curtain of flame tongues
-- erupts over a boiling base of fire-burst flipbooks with a white-hot core low in the
-- middle, inside a swirl of wind arcs. It sways and burns ~2.2 s (dark charcoal tongues at
-- its edges, curls, flecks, embers, fire-tinted smoke rising off it), narrows to a thin
-- bundle and dies, and the crack cools from orange to dark.
-- Layers: crack (dark rift, hot line, red pool), precursor streaks/rocks/flames/rings/smoke/
-- embers, eruption flash + flare, spike row, splash, wind arcs, tongues (left/right/centre)
-- + dark tongues, fire base + hot core, curls, flecks, embers, fire smoke, hot line, light.
--
-- Every mass of fire is a flipbook particle layer (never one image scaling); the only
-- single-image layers are light (the hot line, glows) and the crack.
--
-- ctx.CFrame: the fissure sits on the ground below it and runs across the view (along
-- ctx.CFrame's RightVector); LookVector points at the viewer. WallLength sizes the fissure,
-- curtain, wind and smoke; Scale sizes everything.
--
-- Every channel (rates, box widths, lifetimes, the light and the crack) is driven by one
-- per-frame loop through ctx.Wait, so slow-mo and VFXScrub freezes work.

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	Rift = "rbxassetid://130357872021925", -- StaticVFXTextures/dark glowing rift (long thin jagged crack, horizontal)
	BranchCrack = "rbxassetid://94057358812878", -- StaticVFXTextures/simple crack (star of branching cracks)
	Rocks = "rbxassetid://14305019062", -- FlipbookTextures/Random Rocks (Grid4x4, one rock per cell)
	FlameStreak = "rbxassetid://104267390423468", -- StaticVFXTextures/Line Spec 3 (tall flame-shaped streak)
	FlamePillar = "rbxassetid://70418763522849", -- FlipbookTextures/Upwards flame pillar (Grid4x4)
	FireTower = "rbxassetid://18456244650", -- FlipbookTextures/Fire Tower (Grid4x4, smooth thin upright wisps)
	FlameWisp = "rbxassetid://16504098653", -- FlipbookTextures/Basic Flame Wisp (Grid4x4)
	RingCurl = "rbxassetid://77001323190674", -- FlipbookTextures/dark fire spec (Grid4x4, 128 cells on a 512 sheet; hollow curls)
	Swirl = "rbxassetid://130391463304711", -- StaticVFXTextures/Swirls21 (crescent arcs)
	LineFlare = "rbxassetid://103854278038347", -- StaticVFXTextures/Blurry Horizontal Flare
	SoftGlow = "rbxassetid://284205403", -- StaticVFXTextures/Blurred Spec 11
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	Flash = "rbxassetid://136210055019402", -- Custom: Starburst (filled spiky shape, white)
	LavaWedge = "rbxassetid://109547847796563", -- Custom: soft flare wedge, bright root at the bottom (64x256)
	LavaRing = "rbxassetid://113782032324685", -- Custom: thick soft, slightly lumpy ring (128x128)
	Glint = Textures.Glint, -- drawn: assets/textures/impact.py
	FireA = Textures.FireBurstA, -- drawn: assets/textures/fire.py (Grid4x4)
	FireB = Textures.FireBurstB, -- drawn: assets/textures/fire.py (Grid4x4)
	Smoke = Textures.DustPuff, -- drawn: assets/textures/fire.py (Grid4x4)
}

local track = Layers.Track

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(255, 120, 30), -- dominant flame orange
	CoreColor = Color3.fromRGB(255, 215, 120), -- hot yellow-white, low in the middle
	EdgeColor = Color3.fromRGB(200, 45, 15), -- deep red tongue tops and crack lava
	DarkColor = Color3.fromRGB(22, 14, 12), -- crack, dark streaks, flecks, dark tongues
	SmokeColor = Color3.fromRGB(105, 100, 98), -- self-lit grey smoke and rocks
	Scale = 2.5, -- 2.5x the original size (fissure ~50 studs long)
	WallLength = 20, -- fissure length (studs); every other size follows it
	-- timing: keep EruptTime >= 0.5, BurnTime >= 0.5 and FadeTime >= 0.7
	EruptTime = 0.69, -- crack -> eruption
	BurnTime = 2.16, -- eruption -> the curtain starts to narrow (~2.85 s)
	FadeTime = 0.8, -- narrowing to a thin bundle, then out (~3.65 s)
	CrackFadeTime = 0.7, -- the crack's glow cooling after the flames are gone
	FlameRate = 100, -- flame tongues / s while burning
	BaseRate = 18, -- fire-burst particles / s boiling at the base
	EmberRate = 10, -- embers / s while burning
	CurlRate = 8, -- orange curls and ring curls / s
	FleckRate = 9, -- dark flecks / s
	DarkTongueRate = 6, -- dark charcoal tongues / s at the curtain's sides
	SmokeRate = 5, -- fire-tinted smoke puffs / s rising off the curtain
	RockCount = 8,
	LightBrightness = 4,
	LightRange = 40, -- studs the eruption light's range grows to as it settles (60 at most)
}

Effect.Linger = 1.6 -- the last fire smoke (slowed to 0.8x: up to 1.6 / 0.8 s)

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local F = p.WallLength * s -- crack length
	local B = 0.72 * F -- body: the curtain, precursor, wind and smoke cover the middle of the crack

	local ground = Layers.Ground(ctx)
	local frame = Layers.Frame(ctx, ground) -- +X along the fissure, +Z toward the viewer

	-- Box emitters (particles spawn anywhere in the part). Flame quads are centred on the
	-- particle, so flame boxes sit higher to keep the ground from slicing them.
	local function box(x, y, width)
		local part = ctx.Anchor(frame * CFrame.new(x, y, 0))
		part.Size = Vector3.new(width, 0.2 * s, 1 * s)
		return part
	end
	local line = box(0, 0.6 * s, 0.75 * B) -- the middle of the fissure
	local burstBox = box(0, 0.6 * s, 0.65 * B) -- precursor streaks, then the dark side tongues
	local midFlames = box(0, 0.07 * B, 0.6 * B) -- precursor flames, rocks, smoke
	local tallLeft = box(-0.25 * B, 0.24 * B, 0.5 * B) -- tongue halves; widths follow the curtain
	local tallRight = box(0.25 * B, 0.24 * B, 0.5 * B)
	local tallCentre = box(0, 0.27 * B, 0.3 * B) -- taller tongues, middle of the curtain
	local baseBox = box(0, 0.1 * B, 0.6 * B) -- the boiling fire base
	local smokeBox = box(0, 0.7 * B, 0.5 * B) -- smoke rising off the top of the curtain

	local base = ctx.Anchor(frame)
	local centre = Layers.Attachment(base, CFrame.new(0, 0.4 * s, 0))
	local coreAt = Layers.Attachment(base, CFrame.new(0, 0.12 * B, 0))
	local flashAt = Layers.Attachment(base, CFrame.new(0, 0.1 * B, 0))
	local windHigh = Layers.Attachment(base, CFrame.new(0, 0.35 * B, 0) * CFrame.Angles(math.rad(-20), 0, math.rad(8)))

	------------------------------------------------------------------ crack
	-- The rift on the ground: a dark jagged crack, a thin hot line along it and a faint red
	-- pool, heating before the eruption and cooling after. SurfaceGuis with LightInfluence 0
	-- so Brightness glows; a Top-face SurfaceGui runs the image's X along the part's Z, so
	-- each part is turned to lay the rift along the fissure.
	local function crackLayer(name, depth, length, image, color, lift)
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
	local lineGui, crackLine = crackLayer("CrackLine", 4 * s, F * 0.36, ASSETS.Rift, p.Color, 0.02)
	local poolGui, crackPool = crackLayer("CrackPool", 3 * s, F * 0.45, ASSETS.SoftGlow, p.EdgeColor, 0.01)

	------------------------------------------------------------------ precursor
	local flameColor = { { 0, p.CoreColor }, { 0.35, p.Color }, { 0.75, p.EdgeColor }, { 1, p.EdgeColor:Lerp(p.DarkColor, 0.4) } }
	local streakOrange = Layers.Emitter(burstBox, {
		Texture = ASSETS.FlameStreak,
		Orientation = "FacingCameraWorldUp",
		EmissionDirection = "Top",
		Color = { { 0, p.Color }, { 1, p.EdgeColor } },
		LightEmission = 0.3,
		Brightness = 4,
		Size = { { 0, 1.8 * s, 0.4 * s }, { 1, 1.4 * s } },
		Squash = 0.6,
		Transparency = { { 0, 0 }, { 0.6, 0.2 }, { 1, 1 } },
		Lifetime = { 0.035, 0.055 },
		Speed = { 6 * s, 14 * s },
		SpreadAngle = 6,
		ZOffset = 1,
	})
	-- black twins of the streaks, slower, breaking the burst up
	local streakDark = Layers.Black(streakOrange, 0.2, { Speed = { 4 * s, 9 * s }, Lifetime = { 0.04, 0.06 }, Squash = 0.8 })
	local rocks = Layers.Emitter(midFlames, {
		Texture = { Id = ASSETS.Rocks, Grid = 4 },
		FlipbookMode = "Loop",
		FlipbookFramerate = 0,
		FlipbookStartRandom = true, -- one rock per particle
		EmissionDirection = "Top",
		Color = p.SmokeColor,
		LightEmission = 0,
		Brightness = 1.3,
		Size = { { 0, 0.9 * s, 0.25 * s }, { 0.8, 0.85 * s }, { 1, 0 } },
		Squash = 0.35,
		Lifetime = { 0.2, 0.3 },
		Speed = { 12 * s, 20 * s },
		SpreadAngle = 18,
		Acceleration = Vector3.new(0, -60 * s, 0),
		Drag = 3,
		Rotation = { -25, 25 },
		RotSpeed = { -90, 90 },
		ZOffset = 0.5,
	})
	local preFlames = Layers.Emitter(midFlames, {
		Texture = { Id = ASSETS.FlamePillar, Grid = 4 },
		FlipbookMode = "Loop", -- first frames are tiny: random start
		FlipbookFramerate = { 18, 24 },
		FlipbookStartRandom = true,
		Orientation = "FacingCameraWorldUp",
		EmissionDirection = "Top",
		Color = flameColor,
		LightEmission = 0.3,
		Brightness = 3,
		Size = { { 0, 1.5 * s }, { 0.4, 2.1 * s, 0.3 * s }, { 1, 1.8 * s } },
		Squash = 0.4,
		Transparency = { { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } },
		Lifetime = { 0.12, 0.16 },
		Speed = { 1 * s, 2 * s },
		Rotation = { -8, 8 },
		ZOffset = 1,
	})
	local rings = Layers.Emitter(line, {
		Texture = ASSETS.LavaRing,
		EmissionDirection = "Top",
		Color = p.Color,
		LightEmission = 1,
		Brightness = 1.5,
		Size = { { 0, 0.85 * s, 0.1 * s }, { 1, 0.6 * s } },
		Transparency = { { 0, 0 }, { 0.7, 0.15 }, { 1, 1 } },
		Lifetime = { 0.12, 0.26 },
		Speed = { 10 * s, 18 * s },
		SpreadAngle = 35,
		Drag = 4,
		Rotation = { 0, 360 },
		ZOffset = 1.5,
	})
	local ringCurls = Layers.Emitter(line, {
		Texture = { Id = ASSETS.RingCurl, Grid = 4 },
		FlipbookMode = "Loop", -- early cells are tiny dots: random start
		FlipbookFramerate = { 10, 14 },
		FlipbookStartRandom = true,
		EmissionDirection = "Top",
		Color = { { 0, p.Color }, { 1, p.EdgeColor } },
		LightEmission = 1,
		Brightness = 1.4,
		Size = { { 0, 1.3 * s, 0.2 * s }, { 1, 1.5 * s } },
		Lifetime = { 0.3, 0.45 },
		Speed = { 8 * s, 16 * s },
		SpreadAngle = 35,
		Acceleration = Vector3.new(0, -4 * s, 0),
		Drag = 4,
		Rotation = { 0, 360 },
		ZOffset = 1.5,
	})
	-- smoke plumes shoot up under heavy drag: a grey veil (dark smoke is never a dense black puff)
	local plumes = Layers.Emitter(midFlames, {
		Texture = ASSETS.Smoke,
		EmissionDirection = "Top",
		Color = p.SmokeColor:Lerp(p.DarkColor, 0.35),
		LightEmission = 0,
		Brightness = 1.3,
		Size = { { 0, 2.6 * s }, { 1, 5.2 * s, 1.1 * s } },
		Transparency = { { 0, 0.6 }, { 0.3, 0.5 }, { 1, 1.1 } },
		Lifetime = { 0.24, 0.3 },
		Speed = { 55 * s, 75 * s },
		SpreadAngle = 10,
		Drag = 12,
		Rotation = { 0, 360 },
		RotSpeed = { -30, 30 },
		ZOffset = -1,
	})
	local embers = Layers.Emitter(line, {
		Texture = ASSETS.Speck,
		EmissionDirection = "Top",
		Color = { { 0, p.CoreColor }, { 0.4, p.Color }, { 1, p.EdgeColor } },
		LightEmission = 1,
		Brightness = 1.5,
		Size = { { 0, 0.35 * s, 0.1 * s }, { 0.8, 0.3 * s }, { 1, 0 } },
		Lifetime = { 0.6, 1.1 },
		Speed = { 6 * s, 16 * s },
		SpreadAngle = 35,
		Acceleration = Vector3.new(2 * s, -6 * s, 0),
		Drag = 1.2,
		ZOffset = 2,
	})

	------------------------------------------------------------------ eruption
	-- the flash runs along the crack: a filled spiky shape stretched wide, and a flare line
	local flash = Layers.Emitter(flashAt, {
		Texture = ASSETS.Flash,
		Lifetime = 0.09,
		Rotation = { -6, 6 },
		LightEmission = 0,
		Brightness = 8,
		ZOffset = 4,
		Color = { { 0, p.CoreColor }, { 1, p.Color } },
		Size = { { 0, 0.15 * B }, { 0.3, 0.55 * B }, { 1, 0.6 * B } },
		Squash = -1.2, -- wider than tall: it lies along the crack
		Transparency = { { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } },
	})
	local flare = Layers.Emitter(flashAt, {
		Texture = ASSETS.Glint,
		Lifetime = 0.08,
		LightEmission = 1,
		Brightness = 7,
		ZOffset = 4.1,
		Color = p.CoreColor,
		Size = { { 0, 0.6 * B }, { 1, 0.75 * B } },
		Squash = -6,
		Transparency = { { 0, 0 }, { 1, 1 } },
	})
	local spikes = Layers.Emitter(midFlames, {
		Texture = ASSETS.FlameStreak,
		Orientation = "FacingCameraWorldUp",
		EmissionDirection = "Top",
		Color = { { 0, p.CoreColor }, { 0.4, p.Color }, { 1, p.EdgeColor } },
		LightEmission = 0.3,
		Brightness = 5,
		Size = { { 0, 1 * s, 0.45 * s }, { 1, 1.15 * s, 0.45 * s } },
		Rotation = { -10, 10 },
		Squash = 0.8,
		Transparency = { { 0, 0 }, { 0.7, 0 }, { 1, 1 } },
		Lifetime = { 0.035, 0.055 },
		Speed = { 6 * s, 12 * s },
		ZOffset = 2,
	})
	local splash = Layers.Emitter(line, {
		Texture = ASSETS.LavaWedge,
		Orientation = "VelocityParallel",
		EmissionDirection = "Front", -- across the fissure, fanned all round flat
		Color = { { 0, p.CoreColor }, { 1, p.Color } },
		LightEmission = 0.4,
		Brightness = 2.5,
		Size = { { 0, 1.5 * s }, { 1, 1.9 * s } },
		Squash = 0.7,
		Rotation = -90, -- VelocityParallel: -90 puts the image's top first
		Transparency = { { 0, 0 }, { 0.6, 0.25 }, { 1, 1 } },
		Lifetime = { 0.06, 0.09 },
		Speed = { 25 * s, 40 * s },
		SpreadAngle = { 5, 180 },
		ZOffset = 3,
	})

	-- flame tongues: solid colour carrying a value gradient (hot root, orange, deep red tops),
	-- shooting up fast and dying young; the centre band is taller so the silhouette tapers
	local TONGUE_RUSH = 1.6
	local tongueLifeK = 0.95 / TONGUE_RUSH
	local function tongueSize(height)
		local h = B * height
		return { { 0, 0.21 * h, 0.065 * h }, { 0.5, 0.26 * h, 0.075 * h }, { 1, 0.24 * h, 0.07 * h } }
	end
	local function tongueEmitter(anchor, inward, height)
		return Layers.Emitter(anchor, {
			Texture = { Id = ASSETS.FireTower, Grid = 4 },
			FlipbookMode = "Loop", -- random start: no tiny first frames
			FlipbookFramerate = { 24, 30 },
			FlipbookStartRandom = true,
			Orientation = "FacingCameraWorldUp",
			EmissionDirection = "Top",
			Color = { { 0, p.CoreColor }, { 0.3, p.Color }, { 0.75, p.EdgeColor }, { 1, p.EdgeColor } },
			LightEmission = 0.3,
			Brightness = 4,
			Size = tongueSize(height),
			Squash = { { 0, 0.3 }, { 1, 0.6 } }, -- wide tongues overlap: no gaps
			Transparency = { { 0, 0.05 }, { 0.5, 0.15 }, { 0.65, 0.35 }, { 1, 1 } },
			Lifetime = { 0.35 * tongueLifeK, 0.55 * tongueLifeK },
			Speed = { 0.44 * B * height * TONGUE_RUSH, 0.74 * B * height * TONGUE_RUSH },
			Drag = 1.5,
			SpreadAngle = 4,
			-- positive Rotation turns counter-clockwise on screen (tops lean left)
			Rotation = { math.min(0, inward * 5), math.max(0, inward * 5) },
			ZOffset = 1,
		})
	end
	local tonguesLeft = tongueEmitter(tallLeft, -1, 0.8)
	local tonguesRight = tongueEmitter(tallRight, 1, 0.8)
	local tonguesCentre = tongueEmitter(tallCentre, 0, 1.45)
	local function setTongueSpeed(k)
		k *= TONGUE_RUSH
		tonguesLeft.Speed = NumberRange.new(0.44 * B * 0.8 * k, 0.74 * B * 0.8 * k)
		tonguesRight.Speed = tonguesLeft.Speed
		tonguesCentre.Speed = NumberRange.new(0.44 * B * 1.45 * k, 0.74 * B * 1.45 * k)
	end
	-- dark charcoal tongues at the curtain's edges (black-ish flame silhouettes)
	local darkTongues = Layers.Emitter(burstBox, {
		Texture = { Id = ASSETS.FlamePillar, Grid = 4 },
		FlipbookMode = "Loop",
		FlipbookFramerate = { 14, 18 },
		FlipbookStartRandom = true,
		Orientation = "FacingCameraWorldUp",
		EmissionDirection = "Top",
		Color = p.DarkColor,
		LightEmission = 0,
		Size = { { 0, 0.12 * B }, { 0.5, 0.16 * B }, { 1, 0.14 * B } },
		Squash = 0.5,
		Transparency = { { 0, 0.05 }, { 0.6, 0.2 }, { 1, 1 } },
		Lifetime = { 0.3, 0.45 },
		Speed = { 0.15 * B, 0.3 * B },
		Rotation = { -15, 15 },
		Drag = 1.5,
		ZOffset = 1.5,
	})
	-- the boiling fire base: drawn fire bursts that grow, char and break up low along the crack
	local fireBase = Layers.Emitter(baseBox, {
		Texture = ASSETS.FireA,
		EmissionDirection = "Top",
		SpreadAngle = 40,
		Lifetime = { 0.5, 0.8 },
		Speed = { 0.1 * B, 0.25 * B },
		Drag = 3,
		Rotation = { 0, 360 },
		RotSpeed = { -40, 40 },
		LightEmission = 0.2,
		Brightness = 5,
		ZOffset = 0.8,
		Color = flameColor,
		Size = { { 0, 0.12 * B, 0.03 * B }, { 0.3, 0.26 * B, 0.05 * B }, { 1, 0.3 * B, 0.05 * B } },
	})
	local fireBaseB = Layers.Twin(fireBase, { Texture = ASSETS.FireB, ZOffset = 0.85 })
	-- the white-hot core low in the middle: a small hot copy at high Brightness
	local hotCore = Layers.Emitter(coreAt, {
		Texture = ASSETS.FireB,
		Lifetime = { 0.25, 0.35 },
		Speed = { 0.05 * B, 0.12 * B },
		EmissionDirection = "Top",
		SpreadAngle = 30,
		Rotation = { 0, 360 },
		LightEmission = 0.2,
		Brightness = 15,
		ZOffset = 1.6,
		Color = { { 0, Layers.WHITE }, { 0.5, p.CoreColor }, { 1, p.Color } },
		Size = { { 0, 0.08 * B }, { 0.3, 0.16 * B, 0.03 * B }, { 1, 0.18 * B } },
	})
	local curls = Layers.Emitter(line, {
		Texture = { Id = ASSETS.FlameWisp, Grid = 4 },
		EmissionDirection = "Top",
		Color = flameColor,
		LightEmission = 0.3,
		Brightness = 3,
		Size = { { 0, 0.8 * s }, { 0.5, 1.6 * s, 0.4 * s }, { 1, 1.4 * s } },
		Lifetime = { 0.4, 0.7 },
		Speed = { 5 * s, 12 * s },
		SpreadAngle = 50,
		Acceleration = Vector3.new(0, -10 * s, 0),
		Rotation = { -40, 40 },
		ZOffset = 2,
	})
	local flecks = Layers.Black(curls, 0.5, {
		Color = p.DarkColor,
		Size = { { 0, 0.6 * s }, { 0.5, 1.1 * s, 0.3 * s }, { 1, 0.9 * s } },
		Lifetime = { 0.35, 0.6 },
		Speed = { 4 * s, 10 * s },
		SpreadAngle = 30,
		Acceleration = Vector3.new(0, -12 * s, 0),
	})
	-- smoke rising off the curtain, lit orange by the fire, slowed while it hangs
	local fireSmoke = Layers.Emitter(smokeBox, {
		Texture = ASSETS.Smoke,
		EmissionDirection = "Top",
		SpreadAngle = 20,
		Lifetime = { 1.2, 1.6 },
		Speed = { 0.3 * B, 0.5 * B },
		Drag = 2,
		Rotation = { 0, 360 },
		RotSpeed = { -20, 20 },
		LightEmission = 0,
		Brightness = 1.5,
		ZOffset = -0.5,
		Color = { { 0, p.Color:Lerp(p.SmokeColor, 0.4) }, { 0.35, p.SmokeColor }, { 1, p.SmokeColor } },
		Size = { { 0, 0.15 * B, 0.03 * B }, { 1, 0.4 * B, 0.06 * B } },
		Transparency = { { 0, 0.7 }, { 0.2, 0.35 }, { 1, 1.1 } },
	})
	-- wind: nearly transparent peach arcs round the base, flat and raised + tilted, rising
	-- as they spin out
	local windHalf = 0.5 * B
	local windColor = p.CoreColor:Lerp(Layers.WHITE, 0.4)
	local function windEmitter(att, sizeScale)
		return Layers.Emitter(att, {
			Texture = ASSETS.Swirl,
			Orientation = "VelocityPerpendicular",
			EmissionDirection = "Top",
			Color = { { 0, windColor }, { 1, p.Color } },
			LightEmission = 1,
			Brightness = 0.8,
			Size = { { 0, windHalf * 1.25 * sizeScale }, { 0.5, windHalf * 1.55 * sizeScale }, { 1, windHalf * 1.7 * sizeScale } },
			Squash = -0.45,
			Transparency = { { 0, 0.5 }, { 0.55, 0.65 }, { 1, 1.1 } },
			Lifetime = { 0.42, 0.5 },
			Speed = { 1 * B, 1.2 * B },
			Drag = 2.5,
			Rotation = { -10, 10 },
			RotSpeed = { 30, 60 },
		})
	end
	local windGround = windEmitter(centre, 1)
	local windTilt = windEmitter(windHigh, 0.75)

	-- hot line along the whole crack: light, so one image is right (a horizontal flare)
	local lineLeft = Layers.Attachment(base, CFrame.new(-F * 0.5, 0.12 * s, 0))
	local lineRight = Layers.Attachment(base, CFrame.new(F * 0.5, 0.12 * s, 0))
	local hotLine = Instance.new("Beam")
	Layers.Apply(hotLine, {
		Name = "HotLine",
		Attachment0 = lineLeft,
		Attachment1 = lineRight,
		FaceCamera = true,
		Segments = 1,
		Texture = ASSETS.LineFlare,
		TextureMode = "Stretch",
		Color = p.Color,
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 8,
		Width0 = 1.2 * s,
		Width1 = 1.2 * s,
		Transparency = 1,
		ZOffset = 3,
	})
	hotLine.Parent = base

	local light = Layers.Light(midFlames, { Color = p.Color, Range = 8 * s })

	------------------------------------------------------------------ timeline
	local E = p.EruptTime
	local burnEnd = E + p.BurnTime
	local fadeEnd = burnEnd + p.FadeTime
	local crackEnd = fadeEnd + p.CrackFadeTime

	-- one-off bursts, at most one per loop step (a box moved between emits in the same
	-- frame would spawn every burst at its last position)
	local bursts = {
		{ 0.04, function()
			ctx.Emit(streakOrange, 10)
			ctx.Emit(streakDark, 10)
		end },
		{ 0.042, function()
			ctx.Emit(rocks, p.RockCount)
			ctx.Emit(preFlames, 5)
		end },
		{ 0.075, function()
			ctx.Emit(plumes, 9)
		end },
		{ 0.09, function()
			ctx.Emit(rings, 2)
		end },
		{ 0.11, function()
			ctx.Emit(preFlames, 6)
			ctx.Emit(plumes, 8)
		end },
		{ 0.13, function()
			ctx.Emit(rings, 2)
		end },
		{ 0.15, function()
			ctx.Emit(plumes, 5)
		end },
		{ 0.17, function()
			ctx.Emit(preFlames, 6)
		end },
		{ 0.23, function()
			ctx.Emit(preFlames, 6)
		end },
		{ 0.27, function()
			ctx.Emit(preFlames, 5)
		end },
		{ E - 0.03, function()
			burstBox.CFrame = frame * CFrame.new(0, 0.6 * s, 0)
			burstBox.Size = Vector3.new(0.8 * B, 0.2 * s, 1 * s)
		end },
		{ E, function()
			ctx.Emit(flash, 1)
			ctx.Emit(flare, 1)
			ctx.Emit(spikes, 30)
			ctx.Emit(streakDark, 8)
			-- a flash that settles to the burning glow while its range grows
			light.Brightness = p.LightBrightness * 2.5
			ctx.Tween(light, 0.6, { Brightness = p.LightBrightness, Range = math.min(p.LightRange, 60) })
		end },
		{ E + 0.006, function()
			ctx.Emit(splash, 14)
			ctx.Emit(tonguesLeft, 12)
			ctx.Emit(tonguesRight, 12)
			ctx.Emit(tonguesCentre, 8)
			ctx.Emit(fireBase, 6)
			ctx.Emit(hotCore, 3)
		end },
		{ E + 0.02, function()
			ctx.Emit(windGround, 2)
		end },
		{ E + 0.09, function()
			ctx.Emit(windTilt, 1)
			ctx.Emit(curls, 8)
			ctx.Emit(flecks, 6)
		end },
		{ E + 0.14, function()
			ctx.Emit(windGround, 1)
		end },
		{ E + 0.22, function()
			ctx.Emit(windTilt, 1)
			-- now the dark side tongue spot, starting at the curtain's right edge
			burstBox.Size = Vector3.new(0.08 * B, 0.2 * s, 1 * s)
			burstBox.CFrame = frame * CFrame.new(0.36 * B, 0.12 * B, 0)
		end },
	}
	local nextBurst = 1
	local darkSide = 1

	-- channel rates over time (per second)
	local edgeBurning = { { E + 0.01, 0 }, { E + 0.04, 1 }, { burnEnd, 1 }, { burnEnd + 0.1, 0 } }
	local centreBurning = { { E + 0.01, 0 }, { E + 0.04, 1 }, { fadeEnd - 0.1, 1 }, { fadeEnd - 0.05, 0 } }
	local baseBurning = { { E + 0.02, 0 }, { E + 0.06, 1 }, { burnEnd, 1 }, { fadeEnd - 0.2, 0 } }
	local onsetBoost = { { E, 2.5 }, { E + 0.2, 2.5 }, { E + 0.3, 1 } } -- the opening wall is thick
	local onsetRush = { { E - 0.03, 2.8 }, { E + 0.02, 2.8 }, { E + 0.05, 1 } } -- and rushes up
	local channels = {
		{ tonguesLeft, p.FlameRate * 0.5, edgeBurning, boost = true },
		{ tonguesRight, p.FlameRate * 0.5, edgeBurning, boost = true },
		{ tonguesCentre, p.FlameRate * 0.3, centreBurning, boost = true },
		{ fireBase, p.BaseRate * 0.5, baseBurning },
		{ fireBaseB, p.BaseRate * 0.5, baseBurning },
		{ hotCore, p.BaseRate * 0.4, { { E + 0.04, 0 }, { E + 0.1, 1 }, { burnEnd + 0.3, 1 }, { fadeEnd - 0.2, 0 } } },
		{ darkTongues, p.DarkTongueRate, { { E + 0.3, 0 }, { E + 0.4, 1 }, { burnEnd, 1 }, { burnEnd + 0.2, 0 } } },
		{ embers, p.EmberRate, { { E, 0 }, { E + 0.1, 1 }, { burnEnd, 1 }, { burnEnd + 0.3, 0.2 }, { fadeEnd - 0.1, 0 } } },
		{ curls, p.CurlRate, { { E + 0.1, 0 }, { E + 0.15, 1 }, { burnEnd - 0.2, 1 }, { burnEnd, 0 } } },
		{ ringCurls, p.CurlRate * 0.6, { { E + 0.1, 0 }, { E + 0.15, 1 }, { burnEnd - 0.3, 1 }, { burnEnd, 0 } } },
		{ flecks, p.FleckRate, { { E + 0.1, 0 }, { E + 0.15, 1 }, { burnEnd - 0.1, 1 }, { burnEnd + 0.1, 0 } } },
		{ fireSmoke, p.SmokeRate, { { E + 0.3, 0 }, { E + 0.5, 1 }, { burnEnd + 0.2, 1 }, { fadeEnd - 0.1, 0 } }, slow = 0.8 },
	}
	local owed = table.create(#channels, 0)

	-- the curtain: width (fraction of B) over time, from the onset to a thin bundle
	local curtain = {
		{ E, 0.7 }, { E + 0.03, 0.85 }, { E + 0.3, 0.72 }, { burnEnd, 0.72 },
		{ burnEnd + 0.12, 0.22 }, { burnEnd + 0.45, 0.17 }, { burnEnd + 0.62, 0.05 }, { fadeEnd, 0.02 },
	}
	local tongueLife = { { burnEnd + 0.45, 1 }, { fadeEnd - 0.1, 0.5 } } -- nothing lingers past the end
	local edgeLife = { { burnEnd, 1 }, { burnEnd + 0.1, 0.4 } }
	local centreSize = { { burnEnd, 1 }, { burnEnd + 0.4, 0.9 }, { burnEnd + 0.65, 0.75 } }
	local swayAmount = { { E + 0.1, 0 }, { E + 0.35, 1 }, { burnEnd + 0.1, 1 }, { burnEnd + 0.25, 0 } }
	local swayRight = frame.RightVector
	local swayed = { tonguesLeft, tonguesRight, tonguesCentre }
	local lightTrack = { { E + 0.6, p.LightBrightness }, { burnEnd, p.LightBrightness }, { fadeEnd, 0 } }
	local lineTrack = { { E + 0.012, 1 }, { E + 0.05, 0 }, { burnEnd + 0.4, 0 }, { fadeEnd + 0.2, 1 } }
	local lineWidth = { { E, 1.2 * s }, { E + 0.03, 3.2 * s }, { E + 0.22, 1.2 * s } }
	-- the crack heats before the eruption and cools to dark after it
	local crackDarkTrack = { { 0.03, 1 }, { 0.09, 0.15 }, { E, 0.15 }, { E + 0.1, 0.55 }, { fadeEnd, 0.4 }, { crackEnd, 1 } }
	local crackLineTrack = { { 0.3, 1 }, { 0.5, 0.1 }, { E, 0 }, { fadeEnd, 0.15 }, { crackEnd, 1 } }
	local crackPoolTrack = { { 0.3, 1 }, { 0.5, 0.45 }, { E, 0.4 }, { E + 0.2, 0.7 }, { fadeEnd, 0.8 }, { crackEnd, 1 } }
	local crackBrightTrack = { { 0.3, 1 }, { 0.6, 2.6 }, { E + 0.1, 3.2 }, { fadeEnd, 2 }, { crackEnd, 0.6 } }
	local crackColorTrack = { { fadeEnd, p.Color }, { crackEnd, p.EdgeColor:Lerp(p.DarkColor, 0.6) } }

	local last = {}
	local function changed(key, value, apply)
		if last[key] == nil or math.abs(last[key] - value) > 1e-3 then
			last[key] = value
			apply(value)
		end
	end

	local t = 0
	while t < crackEnd and ctx.Folder.Parent do
		local burst = bursts[nextBurst]
		if burst and t >= burst[1] then
			burst[2]()
			nextBurst += 1
		end

		local dt = ctx.Wait(1 / 240) -- every rendered frame, so the ~30 ms pops hold up in slow-mo
		t += dt

		for i, channel in channels do
			local rate = channel[2] * track(channel[3], t)
			if channel.boost then
				rate *= track(onsetBoost, t)
			end
			owed[i] += rate * dt
			local n = math.floor(owed[i])
			if n > 0 then
				owed[i] -= n
				Layers.Emit(ctx, channel[1], n, channel.slow)
				if channel[1] == darkTongues then
					-- the next dark tongue on the other edge (moving the box after emitting)
					darkSide = -darkSide
					burstBox.CFrame = frame * CFrame.new(darkSide * track(curtain, t) * B * 0.48, 0.12 * B, 0)
				end
			end
		end

		local rush = track(onsetRush, t)
		changed("rush", rush, setTongueSpeed)
		local life = track(tongueLife, t) * tongueLifeK / rush
		local edge = math.min(track(tongueLife, t), track(edgeLife, t)) * tongueLifeK / rush
		changed("edge", edge, function(k)
			tonguesLeft.Lifetime = NumberRange.new(0.35 * k, 0.55 * k)
			tonguesRight.Lifetime = tonguesLeft.Lifetime
		end)
		changed("life", life, function(k)
			tonguesCentre.Lifetime = NumberRange.new(0.35 * k, 0.55 * k)
		end)
		changed("centreSize", track(centreSize, t), function(k)
			tonguesCentre.Size = Layers.Seq(tongueSize(1.45 * k))
		end)

		-- the boxes follow the curtain's width
		local width = track(curtain, t) * B
		tallLeft.Size = Vector3.new(width / 2, 0.2 * s, 1 * s)
		tallRight.Size = tallLeft.Size
		tallLeft.CFrame = frame * CFrame.new(-width / 4, 0.24 * B, 0)
		tallRight.CFrame = frame * CFrame.new(width / 4, 0.24 * B, 0)
		tallCentre.Size = Vector3.new(width * 0.6, 0.2 * s, 1 * s)
		baseBox.Size = Vector3.new(width * 0.8, 0.2 * s, 1 * s)
		smokeBox.Size = Vector3.new(width * 0.7, 0.2 * s, 1 * s)
		-- two mixed sines (~0.9 and ~1.6 sways/s) so the swing never looks mechanical
		local sway = track(swayAmount, t) * (0.75 * math.sin(t * 5.7) + 0.25 * math.sin(t * 10.1 + 1.3))
		local push = swayRight * (1.6 * B * sway)
		for _, e in swayed do
			e.Acceleration = push
		end

		if t > E + 0.6 then
			light.Brightness = track(lightTrack, t)
		end
		changed("lineAlpha", track(lineTrack, t), function(alpha)
			hotLine.Transparency = Layers.Seq({ { 0, 1 }, { 0.12, alpha }, { 0.88, alpha }, { 1, 1 } })
		end)
		local lw = track(lineWidth, t)
		hotLine.Width0, hotLine.Width1 = lw, lw
		crackDark.ImageTransparency = track(crackDarkTrack, t)
		crackLine.ImageTransparency = track(crackLineTrack, t)
		crackPool.ImageTransparency = track(crackPoolTrack, t)
		crackLine.ImageColor3 = track(crackColorTrack, t)
		lineGui.Brightness = track(crackBrightTrack, t)
		poolGui.Brightness = track(crackBrightTrack, t) * 0.7
	end
end

return Effect
