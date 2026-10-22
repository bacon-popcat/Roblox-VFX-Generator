-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/ChromaticStrike
-- A white, prismatic ranged strike: three white projectiles with smoky trails fly to the target,
-- the caster charges (chromatic ground ring, a black void frame, a huge prismatic
-- starburst) and fires a tunnelling dash along a rainbow ground streak, and the target
-- erupts: a giant jagged white flash with rainbow fringes, a light pillar, halo rings that
-- rise around it, crystal spikes with rainbow tips, RGB glitch bolts, star flashes, cross-flares,
-- leaves and debris, a 4-point cross finale and a crown of arched smoke plumes.
-- Layers: projectiles (sky shots: star heads, core/haze/smoke-edge beam trails; low shots: a
-- thin bright line in a soft streak, the dash's head), caster sparks/void/starburst/rays/
-- crystals/bokeh/dark shell/prismatic sparkle stars and flares, dash head (a flickering spiky
-- white ball, a white splash fanned back, a dark smoke wedge with rainbow slivers, black
-- debris), thin bright line + soft haze back to the caster, glowing orbs along the path,
-- tunnel rings, rainbow ground streak (white centre, drawn behind the head), impact flash (white + red/cyan copies for the
-- fringe), pillar beams, dark ground shockwave, halo rings, crystal spikes, chromatic
-- blobs, glitch ribbons, flares, cross finale, smoke disc, arched plumes, leaves, rocks,
-- sparkles, white-hot core star, blast streaks, ground flash ring, rising motes, light,
-- camera shake (ctx.Shake), screen-edge vignette (magenta left, teal right).
--
-- ctx.CFrame: the target. The impact sits on the ground below it; its LookVector points
-- at the caster, who stands CasterDistance studs away along it (the harness target faces
-- the player). Optional runtime-only override `Caster` (a BasePart, e.g. the caster's
-- HumanoidRootPart): the wires and dash start from it instead.
-- Timeline (effect seconds, measured on a 60 fps reference from 4 takes): wires 0-1.1,
-- charge 1.10, void 1.30, launch + dash 1.33, impact `ImpactTime` 1.85, cross finale
-- `FinaleTime` 3.00, smoke gone by ~4.5.
--
-- One per-frame loop (ctx.Wait(1/240)) runs a time-sorted event list (every burst) and
-- drives the wires, the dash head, the ground streak, the pillar, the light and the
-- vignette, so slow-mo and VFXScrub freezes work. The vignette follows
-- workspace.CurrentCamera (two soft camera-locked glows at the screen edges).

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	Needle = "rbxassetid://10614304526", -- StaticVFXTextures/Sideways Spec 41 (thin needle)
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31 (small solid speck)
	Smoke = "rbxassetid://111394301752764", -- StaticVFXTextures/smoke 41 (soft puff)
	Glow = "rbxassetid://87365446017300", -- lava_glow (custom): round soft glow, zero at the edge
	Sparkle = "rbxassetid://16444981264", -- StaticVFXTextures/Star153 (small 4-point sparkle)
	Star = "rbxassetid://17391818367", -- StaticVFXTextures/Star102 (long 4-point glare)
	Starburst = "rbxassetid://136210055019402", -- Starburst (custom): irregular spikes on a jagged core
	SunRays = "rbxassetid://85455873620937", -- StaticVFXTextures/Smooth Chromatic Sun Ray Lens Flare
	JaggedShard = "rbxassetid://111191563800567", -- StaticVFXTextures/jagged shard spec (white blade)
	ChromLine = "rbxassetid://15989904878", -- StaticVFXTextures/Chromatic Line (vertical rainbow spike)
	ChromWisp = "rbxassetid://107522305986216", -- StaticVFXTextures/Chromatic Wisp (white blob, rainbow sides)
	ChromWisp2 = "rbxassetid://124024586710210", -- StaticVFXTextures/Chromatic Wisp 2
	SoftTrail = "rbxassetid://85104342894286", -- cs_soft_trail (custom): soft fibrous trail strip, uniform along its length so segment joints never show (Python)
	RgbBolt = "rbxassetid://100904020799857", -- cs_rgb_bolt (custom): black-edged RGB-split zigzag bolt, colour baked (Codex image_gen)
	LineFlare = "rbxassetid://103854278038347", -- StaticVFXTextures/Blurry Horizontal Flare (thin white line)
	ChromRing = "rbxassetid://109324703201714", -- StaticVFXTextures/Chromatic Smoke Circle
	WispSphere = "rbxassetid://115949955697406", -- FlipbookTextures/Wispy Sphere 4x4 (Grid4x4)
	DarkDisc = "rbxassetid://107972524433656", -- StaticVFXTextures/Blurry Black Hole (soft dark disc)
	NeonRing = "rbxassetid://15268062056", -- StaticVFXTextures/thick ring 3 (crisp inner edge, soft glow)
	BandRing = "rbxassetid://15058135927", -- StaticVFXTextures/thick ring 2 (soft medium band)
	SmokeRing = "rbxassetid://12318427672", -- StaticVFXTextures/Smokey Shockwave (grey wind ring)
	BlackEnergy = "rbxassetid://17511030724", -- FlipbookTextures/Glowing Black Energy (Grid4x4)
	-- made for this effect (white RGB, shape in alpha) and uploaded
	HaloThin = "rbxassetid://118128517935651", -- cs_halo_thin: crisp thin ring at 0.86 of the half-width, tight glow (Python)
	ImpactFlash = "rbxassetid://106031250604546", -- cs_impact_flash: jagged V-wing flash mass, wider than tall (Codex image_gen)
	SmokeHook = "rbxassetid://134858289383590", -- cs_smoke_hook: smoky arched hook stroke, 1:2 tall (Codex image_gen)
	Leaf = "rbxassetid://138965102259499", -- FlipbookTextures/green leaf spinning (Grid4x4, green baked in)
	Rocks = "rbxassetid://14305019062", -- FlipbookTextures/Random Rocks (Grid4x4, one rock per cell)
	WireBeam = "rbxassetid://134298856602125", -- MigratedBeams/BeamThinJaggedStreak (wavy white line)
	RainbowStreak = "rbxassetid://134095631127258", -- MigratedBeams/BeamChromaticStreak (twin rainbow rails)
	DashSwirl = "rbxassetid://17388445727", -- StaticVFXTextures/Crescent32 (layered crescent strokes)
	PillarCore = "rbxassetid://7135001284", -- MigratedBeams/BeamStretchedGlowColumn
	PillarLines = "rbxassetid://6091329339", -- MigratedBeams/BeamGlowingStreakLines
	PillarDark = "rbxassetid://15398097961", -- MigratedBeams/BeamFlickeringSmokeColumn (tinted black)
}

local WHITE = Color3.new(1, 1, 1)
local LINE = Color3.fromRGB(255, 244, 214) -- the shots' thin bright line, a little warm
local UP = Vector3.yAxis

--------------------------------------------------------------------------------
-- helpers

local function seq(points)
	local keypoints = {}
	for _, point in points do
		table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2], point[3] or 0))
	end
	return NumberSequence.new(keypoints)
end

-- constant size, random per particle between lo and hi (a NumberSequence envelope)
local function sizeRange(lo, hi)
	local mid, env = (lo + hi) / 2, (hi - lo) / 2
	return seq({ { 0, mid, env }, { 1, mid, env } })
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
	e.LightEmission = 1
	e.Color = ColorSequence.new(WHITE)
	for key, value in props do
		e[key] = value
	end
	e.Parent = parent
	return e
end

local function attachment(parent, worldCFrame)
	local att = Instance.new("Attachment")
	att.Parent = parent
	att.WorldCFrame = worldCFrame
	return att
end

local function beam(a0, a1, props)
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.LightInfluence = 0
	b.LightEmission = 1
	b.Segments = 20
	b.TextureMode = Enum.TextureMode.Stretch
	b.TextureLength = 1
	for key, value in props do
		b[key] = value
	end
	b.Parent = a0.Parent
	return b
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

-- Ground point below a position, skipping characters (same as FireballExplosion).
local function findGround(origin, exclude)
	local params = RaycastParams.new()
	params.RespectCanCollide = true
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

-- Catmull-Rom spline through `points` (world Vector3s), s in [0, 1].
local function spline(points, s)
	local n = #points - 1
	local x = math.clamp(s, 0, 1) * n
	local i = math.min(math.floor(x), n - 1)
	local u = x - i
	local p0 = points[math.max(i, 1)]
	local p1 = points[i + 1]
	local p2 = points[i + 2]
	local p3 = points[math.min(i + 3, #points)]
	local u2, u3 = u * u, u * u * u
	return 0.5
		* ((2 * p1) + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (3 * p1 - p0 - 3 * p2 + p3) * u3)
end

-- Attachment frame with X along `tangent` (beams curve along their attachments' X axis).
local function alongFrame(pos, tangent)
	local x = tangent.Magnitude > 1e-4 and tangent.Unit or Vector3.xAxis
	local y = UP - x * UP:Dot(x)
	if y.Magnitude < 1e-3 then
		y = Vector3.zAxis - x * x.Z
	end
	return CFrame.fromMatrix(pos, x, y.Unit)
end

-- Projectile paths: { along (0 caster .. 1 target), height, side (+ = caster's right) }; heights
-- and sides are studs at the default Scale. Measured on two 0.25x recordings (far and behind
-- the caster, cross-checked with Gemini): three white sky projectiles and two low streaks,
-- one streak per caster burst. Each is a bright star head trailing a twisted white smoke
-- ribbon edged with dark smoke; the trail stays drawn from the caster until FadeAt, then fades
-- while its tail pulls in.
local WIRES = {
	{ -- low streak 1 (first burst): chest height, straight, a spiky white head on a dark wedge
		Launch = 0.14,
		Travel = 0.42,
		Soft = true, -- a thin bright line in a soft white streak rather than a kinked rope
		FadeAt = 0.95,
		Fade = 0.18,
		Width = 3,
		Points = { { 0, 3, 0 }, { 0.5, 3.2, 0 }, { 1, 3, 0 } },
	},
	{ -- sky 1: wide overhand loop; up the left, over the top, down the right, hooks in
		Launch = 0.13,
		Travel = 0.56,
		FadeAt = 0.95,
		Fade = 0.22,
		Width = 1.2,
		Points = {
			{ 0, 3, 0 }, { 0.02, 10, -2 }, { 0.08, 18, -4 }, { 0.2, 23, -3 }, { 0.4, 22, 2 },
			{ 0.6, 18, 7 }, { 0.8, 10, 5 }, { 0.95, 6, 1 }, { 1, 4, 0 },
		},
	},
	{ -- sky 2 (second burst): fast, up the left to ~15 studs, a sharp hook, dives across
		Launch = 0.5,
		Travel = 0.31,
		FadeAt = 1.02,
		Fade = 0.18,
		Width = 1.2,
		Points = {
			{ 0, 3, 0 }, { 0.03, 9, -4 }, { 0.08, 14, -6 }, { 0.12, 15.5, -6.5 }, { 0.4, 11, -2 },
			{ 0.75, 6, 0 }, { 1, 4, 0 },
		},
	},
	{ -- low streak 2 (second burst)
		Launch = 0.52,
		Travel = 0.36,
		Soft = true,
		FadeAt = 1.05,
		Fade = 0.15,
		Width = 2.5,
		Points = { { 0, 2.8, 0 }, { 0.5, 3, 0 }, { 1, 3, 0 } },
	},
	{ -- sky 3: the tallest; up the right to ~27 studs (star glint at the apex), S-dives in
		Launch = 0.58,
		Travel = 0.5,
		FadeAt = 1.1,
		Fade = 0.16,
		Width = 1.2,
		Glint = 0.81, -- effect time of the big star flash at its apex
		Points = {
			{ 0, 3, 0 }, { 0.02, 12, 3 }, { 0.06, 22, 3.5 }, { 0.12, 27, 3 }, { 0.25, 24, 6 },
			{ 0.45, 18, 4 }, { 0.6, 14, -2 }, { 0.8, 10, -1 }, { 1, 4, 0 },
		},
	},
}

--------------------------------------------------------------------------------

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(255, 255, 255), -- the light: flash, pillar, rings, spikes
	InkColor = Color3.fromRGB(12, 12, 16), -- wire smudge, void, ink core, dark shell
	SmokeColor = Color3.fromRGB(170, 170, 178), -- ground smoke, plumes
	FringeRed = Color3.fromRGB(255, 70, 60), -- outer rainbow fringe on the impact flash
	FringeBlue = Color3.fromRGB(60, 170, 255), -- inner rainbow fringe on the impact flash
	VignetteLeft = Color3.fromRGB(180, 40, 140), -- magenta screen edge on the big flashes
	VignetteRight = Color3.fromRGB(40, 160, 170), -- teal screen edge
	Scale = 2.5, -- sizes the target eruption; caster bursts, wires and dash use 0.56x of it
	CasterDistance = 32, -- studs from the target to the caster (without a `Caster` override)
	ImpactTime = 1.85, -- effect time of the giant impact flash (dash lands)
	FinaleTime = 3.7, -- the pillar collapses into the 4-point cross (a long burn: ~1.85 s)
	WireWidth = 0.18, -- trail core width (x caster scale); haze and dark edge are a few times wider
	WireSegments = 6, -- beam segments per looping sky trail x 3 beams (fewer = cheaper, angular loops); low streaks use 1
	SmudgeRate = 70, -- smoke smudge puffs / s per wire tip while it travels
	SparkCount = 16, -- caster spark bursts (the later bursts are fractions of it)
	SpeckCount = 16, -- black shrapnel at the impact (the pre-hits use fractions of it)
	BokehCount = 10, -- white dots flying out inside the caster's shell
	SpikeRate = 75, -- sets the crystal spikes per 0.07 s step (SpikeRate * 0.07, split over two fans)
	SmokeRate = 100, -- ground smoke puffs / s while the pillar burns
	LeafCount = 22,
	RockCount = 20,
	PuffCount = 16, -- opaque grey puffs bursting out of the impact
	StreakCount = 36, -- white blast streaks flying out of the impact
	MoteRate = 45, -- white glints rising through the burn / s
	PlumeCount = 12, -- arched smoke hooks in total
	Vignette = true,
	Shake = true, -- camera shake on the launch, the impact, the burn and the finale
	ShakeScale = 1, -- multiplies every shake's strength
	LightBrightness = 3,
	LightRange = 8,
}

Effect.Linger = 1.5 -- smoke disc puffs and plumes outlive the loop (up to ~1.5 s)

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale -- target eruption
	local sc = s * 0.56 -- caster bursts, wires, dash and the target's pre-hits (measured ~0.56x)
	local ink = p.InkColor

	------------------------------------------------------------------ layout
	local exclude = { ctx.Folder }
	local target = findGround(ctx.CFrame.Position, exclude)
	local look = ctx.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	local casterRoot = typeof(p.Caster) == "Instance" and p.Caster:IsA("BasePart") and p.Caster or nil
	local caster
	if casterRoot then
		caster = findGround(casterRoot.Position, { ctx.Folder })
		local flat = (caster - target) * Vector3.new(1, 0, 1)
		if flat.Magnitude > 1 then
			look = flat.Unit
		end
	else
		caster = target + look * p.CasterDistance
	end
	local toTarget = (target - caster) * Vector3.new(1, 0, 1)
	local distance = toTarget.Magnitude
	local dashDir = distance > 0.01 and toTarget.Unit or -look
	local right = dashDir:Cross(UP).Unit -- caster's right, looking at the target
	-- wire path heights and sides (WIRES, studs at the default Scale) follow the caster
	-- scale, so the loops keep their shape at other sizes
	local wireScale = sc / 1.4
	local function linePoint(along, height, side)
		return caster:Lerp(target, along) + UP * height * wireScale + right * side * wireScale
	end

	local tImpact = p.ImpactTime
	local tFinale = p.FinaleTime
	local tLaunch = tImpact - 0.52 -- caster starburst + dash start (1.33)
	local tVoid = tLaunch - 0.035 -- black void frame at the caster (2 frames at 60 fps)
	local tCharge = tLaunch - 0.23 -- target convergence flash + caster chromatic ring (1.10)
	local burnEnd = tFinale + 0.15

	------------------------------------------------------------------ anchors
	local casterPart = ctx.Anchor(CFrame.new(caster + UP * 2.6))
	casterPart.Size = Vector3.new(8, 8, 8) * sc -- orbiting chromatic shards (sphere volume)
	local casterAt = attachment(casterPart, CFrame.new(caster + UP * 2.6))
	-- forward cone (+Y toward the target, a little to the right) for the opening sparks
	local casterFwd = attachment(casterPart, CFrame.fromMatrix(caster + UP * 2.6, -right, (dashDir + right * 0.5).Unit))
	local casterGround = attachment(casterPart, CFrame.new(caster + UP * 0.25))

	local targetPart = ctx.Anchor(CFrame.new(target + UP * 3))
	targetPart.Size = Vector3.new(4, 4, 4)
	local targetAt = attachment(targetPart, CFrame.new(target + UP * 3))

	local base = ctx.Anchor(CFrame.new(target))
	local impactAt = attachment(base, CFrame.new(target + UP * 5 * s)) -- impact flash centre
	local groundAt = attachment(base, CFrame.new(target + UP * 0.25))
	local ringLowAt = attachment(base, CFrame.new(target + UP * 1.7 * s))
	local ringHighAt = attachment(base, CFrame.new(target + UP * 5.4 * s)) -- mid halo ~13.5 studs, rises to ~22
	local flareAt = attachment(base, CFrame.new(target + UP * 5.5 * s)) -- moved per flare
	local crossAt = attachment(base, CFrame.new(target + UP * 7.6 * s))

	-- volumes: spike ring, smoke disc, plume ring
	-- crystal spike fans: camera-facing, so they lean left/right of the viewer's screen
	local viewRight = right
	if workspace.CurrentCamera then
		local r = workspace.CurrentCamera.CFrame.RightVector * Vector3.new(1, 0, 1)
		if r.Magnitude > 0.1 then
			viewRight = r.Unit
		end
	end
	local spikeLeft = attachment(base, CFrame.new(target - viewRight * 1.5 * s + UP * 4.5 * s))
	local spikeRight = attachment(base, CFrame.new(target + viewRight * 1.5 * s + UP * 4.5 * s))
	local glitchPart = ctx.Anchor(CFrame.new(target + UP * 6 * s)) -- box volume over the burn
	glitchPart.Size = Vector3.new(14, 10, 14) * s
	local spikePart = ctx.Anchor(CFrame.new(target + UP * 3 * s))
	spikePart.Size = Vector3.new(18, 0.2, 18) * s
	local smokePart = ctx.Anchor(CFrame.new(target + UP * 2 * s))
	smokePart.Size = Vector3.new(30, 0.2, 30) * s
	local plumePart = ctx.Anchor(CFrame.new(target + UP * 5 * s))
	plumePart.Size = Vector3.new(26, 0.2, 26) * s

	------------------------------------------------------------------ shot heads
	-- A shot's head, as in the reference: a white spiky splash fanned back off it (locked to
	-- the head), a dark smoke wedge trailing it with chromatic slivers on its edges, and black
	-- debris. `back` is the attachment face that points back along the path; k sizes it.
	local function shotHead(att, back, k)
		local kit = {}
		kit.Spikes = emitter(att, {
			Texture = ASSETS.JaggedShard,
			LockedToPart = true,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			EmissionDirection = back,
			SpreadAngle = Vector2.new(40, 40),
			Rate = 70,
			Enabled = false,
			Speed = NumberRange.new(8 * k, 16 * k),
			Drag = 8,
			Lifetime = NumberRange.new(0.06, 0.12),
			Size = seq({ { 0, 0.5 * k }, { 0.3, 1.5 * k, 0.4 * k }, { 1, 1.1 * k } }),
			Transparency = seq({ { 0, 0 }, { 0.7, 0.15 }, { 1, 1 } }),
			Brightness = 3,
			ZOffset = 1.5,
			TimeScale = ctx.TimeScale,
		})
		kit.Wedge = emitter(att, { -- left behind the fast head, so it widens into a wedge
			Texture = ASSETS.Smoke,
			Color = ColorSequence.new(ink),
			LightEmission = 0,
			EmissionDirection = back,
			SpreadAngle = Vector2.new(25, 25),
			Rate = 110,
			Enabled = false,
			Speed = NumberRange.new(1 * k, 4 * k),
			Lifetime = NumberRange.new(0.12, 0.22),
			Size = seq({ { 0, 0.6 * k }, { 0.3, 1.5 * k }, { 1, 2.2 * k } }),
			Transparency = seq({ { 0, 0.1 }, { 0.6, 0.3 }, { 1, 1 } }),
			Rotation = NumberRange.new(0, 360),
			ZOffset = -0.5,
			TimeScale = ctx.TimeScale,
		})
		kit.Sheen = emitter(att, { -- rainbow slivers glancing off the wedge
			Texture = ASSETS.ChromLine,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			EmissionDirection = back,
			SpreadAngle = Vector2.new(35, 35),
			Rate = 45,
			Enabled = false,
			Speed = NumberRange.new(3 * k, 8 * k),
			Drag = 4,
			Lifetime = NumberRange.new(0.08, 0.16),
			Size = seq({ { 0, 0.7 * k }, { 1, 0.4 * k } }),
			Squash = NumberSequence.new(-0.5),
			Rotation = NumberRange.new(-90),
			Transparency = seq({ { 0, 0.1 }, { 1, 0.9 } }),
			Brightness = 2.5,
			ZOffset = 0.2,
			TimeScale = ctx.TimeScale,
		})
		kit.Debris = emitter(att, {
			Texture = ASSETS.Speck,
			Color = ColorSequence.new(ink),
			LightEmission = 0,
			EmissionDirection = back,
			SpreadAngle = Vector2.new(70, 70),
			Rate = 35,
			Enabled = false,
			Speed = NumberRange.new(6 * k, 14 * k),
			Drag = 2,
			Acceleration = Vector3.new(0, -25, 0),
			Lifetime = NumberRange.new(0.25, 0.45),
			Size = sizeRange(0.08 * k, 0.2 * k),
			Rotation = NumberRange.new(0, 360),
			TimeScale = ctx.TimeScale,
		})
		return kit
	end
	local function enableKit(kit, on)
		for _, e in kit do
			e.Enabled = on
		end
	end

	------------------------------------------------------------------ wires
	-- Each projectile trail is WireSegments cubic beam segments from its tail to its tip
	-- along a spline, drawn three times: a bright twisted core, a soft white smoke haze around
	-- it and a wider dark smoke edge behind. The head is a locked bright star.
	local skySegments = math.max(1, math.floor(p.WireSegments))
	local wireSlots = {}
	for slot, wireDef in WIRES do
		-- a nearly straight low streak is one cubic beam: joints show as rungs on a straight trail
		local segments = wireDef.Soft and 1 or skySegments
		local atts = {}
		for i = 1, segments + 1 do
			atts[i] = attachment(base, CFrame.new(caster))
		end
		local b = atts[#atts]
		local core = {
			Texture = wireDef.Soft and "" or ASSETS.WireBeam, -- a low streak's core is a solid thin line
			TextureMode = Enum.TextureMode.Wrap,
			TextureLength = 3 * sc,
			Width0 = p.WireWidth * (wireDef.Soft and 0.8 or wireDef.Width) * sc,
			Width1 = p.WireWidth * (wireDef.Soft and 0.8 or wireDef.Width) * sc,
			Color = ColorSequence.new(wireDef.Soft and LINE or p.Color),
			Brightness = wireDef.Soft and 4 or 3,
			ZOffset = 0.5,
			Enabled = false,
		}
		local hazeProps = {
			Texture = ASSETS.SoftTrail,
			TextureMode = Enum.TextureMode.Wrap,
			TextureLength = 5 * sc,
			TextureSpeed = -0.8,
			Width0 = p.WireWidth * (1.5 + 1.3 * wireDef.Width) * sc,
			Width1 = p.WireWidth * (1.5 + 1.3 * wireDef.Width) * sc,
			Color = ColorSequence.new(p.Color),
			-- near-normal blend: additive haze doubles up where two segments overlap at a joint
			LightEmission = 0.1,
			Brightness = 1.3,
			ZOffset = 0.2,
			Enabled = false,
		}
		local inkProps = {
			Texture = ASSETS.SoftTrail,
			TextureMode = Enum.TextureMode.Wrap,
			TextureLength = 4 * sc,
			TextureSpeed = 0.6,
			Width0 = p.WireWidth * (2.2 + 1.1 * wireDef.Width) * sc,
			Width1 = p.WireWidth * (2.2 + 1.1 * wireDef.Width) * sc,
			Color = ColorSequence.new(ink),
			LightEmission = 0,
			ZOffset = -0.3,
			Enabled = false,
		}
		local tip = emitter(b, { -- bright head + glitter shed along the wire
			Texture = ASSETS.Sparkle,
			Rate = 45,
			Enabled = false,
			Lifetime = NumberRange.new(0.08, 0.5),
			Speed = NumberRange.new(0.5, 2),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -3, 0),
			Size = seq({ { 0, 0.9 * sc }, { 0.15, 0.35 * sc }, { 1, 0 } }),
			Transparency = seq({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }),
			Rotation = NumberRange.new(0, 90),
			Brightness = 3,
			TimeScale = ctx.TimeScale,
		})
		local head = emitter(b, { -- the projectile's head: a bright 4-point star that rides the tip
			Texture = ASSETS.Star,
			LockedToPart = true,
			Rate = 40,
			Enabled = false,
			Speed = NumberRange.new(0),
			Lifetime = NumberRange.new(0.06, 0.09),
			Size = seq({ { 0, 0.75 * sc }, { 1, 0.6 * sc } }), -- ~2 studs across
			Transparency = seq({ { 0, 0 }, { 0.6, 0.2 }, { 1, 1 } }),
			Rotation = NumberRange.new(-8, 8),
			Brightness = 6,
			ZOffset = 1,
			TimeScale = ctx.TimeScale,
		})
		local headGlow = emitter(b, { -- soft glow round it; the low streak's is chromatic
			Texture = wireDef.Soft and ASSETS.ChromWisp or ASSETS.Glow,
			LockedToPart = true,
			Rate = 30,
			Enabled = false,
			Speed = NumberRange.new(0),
			Lifetime = NumberRange.new(0.08, 0.12),
			Size = NumberSequence.new(wireDef.Soft and 0.9 * sc or 0.55 * sc),
			Transparency = seq({ { 0, 0.1 }, { 1, 1 } }),
			Rotation = NumberRange.new(0, 360),
			Brightness = 3,
			ZOffset = 0.8,
			TimeScale = ctx.TimeScale,
		})
		-- a low streak's head is the dash's (shotHead); its dark wedge is the smudge. The
		-- attachments' X runs along the path, so -X (Left) points back
		local kit = wireDef.Soft and shotHead(b, Enum.NormalId.Left, 0.8 * sc) or nil
		local smudge = kit and kit.Wedge or emitter(b, { -- smoke puffs billowing off the tip (grey, a few dark)
			Texture = ASSETS.Smoke,
			Rate = p.SmudgeRate,
			Enabled = false,
			Color = ColorSequence.new(p.SmokeColor:Lerp(ink, 0.6)),
			LightEmission = 0,
			Lifetime = NumberRange.new(0.25, 0.45),
			Speed = NumberRange.new(0.3, 1.2),
			SpreadAngle = Vector2.new(180, 180),
			Size = seq({ { 0, 0.6 * sc }, { 0.3, 1.2 * sc }, { 1, 1.6 * sc } }),
			Transparency = seq({ { 0, 0.4 }, { 0.4, 0.45 }, { 1, 1 } }),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-40, 40),
			TimeScale = ctx.TimeScale,
		})
		local cores, hazes, inks = {}, {}, {}
		for i = 1, segments do
			cores[i] = beam(atts[i], atts[i + 1], core)
			hazes[i] = beam(atts[i], atts[i + 1], hazeProps)
			if not wireDef.Soft then -- the low streaks have no dark edge: their dark is the wedge
				inks[i] = beam(atts[i], atts[i + 1], inkProps)
			end
		end
		wireSlots[slot] = {
			Segments = segments,
			Atts = atts,
			Cores = cores,
			Hazes = hazes,
			Inks = inks,
			Tip = tip,
			Head = head,
			HeadGlow = headGlow,
			Smudge = smudge,
			Kit = kit,
		}
	end
	-- per-play path state lives on the slots: WIRES is shared by every play
	for i, wire in WIRES do
		local world = {}
		for j, point in wire.Points do
			world[j] = linePoint(point[1], point[2], point[3])
		end
		-- the path ends on the target, wherever the caster stands
		world[#world] = target + UP * wire.Points[#wire.Points][2] * wireScale
		wireSlots[i].World = world
		wireSlots[i].Done = false
	end

	local function showWire(slot, on)
		for _, b in slot.Cores do
			b.Enabled = on
		end
		for _, b in slot.Inks do
			b.Enabled = on
		end
		for _, b in slot.Hazes do
			b.Enabled = on
		end
		if not on then
			slot.Tip.Enabled = false
			slot.Head.Enabled = false
			slot.HeadGlow.Enabled = false
			slot.Smudge.Enabled = false
			if slot.Kit then
				enableKit(slot.Kit, false)
			end
		end
	end

	local function updateWire(wire, slot, t)
		local life = t - wire.Launch
		if life < 0 or slot.Done then
			return false
		end
		local tipS = math.clamp(life / wire.Travel, 0, 1)
		tipS = 1 - (1 - tipS) ^ 1.25 -- shoots out fast, eases into the target
		local fadeK = math.clamp((t - wire.FadeAt) / wire.Fade, 0, 1)
		-- a comet wire (Trail < 1) only keeps the last Trail of its path behind the tip
		local tailS = math.max(math.max(tipS - (wire.Trail or 1), 0), 0.35 * fadeK)
		if fadeK >= 0.999 then
			slot.Done = true
			showWire(slot, false)
			return false
		end
		-- place the attachments along the visible stretch, X along the path, and bend each
		-- segment into the spline (cubic Hermite: curve size = path speed * step / 3)
		local segments = slot.Segments
		local step = (tipS - tailS) / segments
		local speeds = {}
		for i, att in slot.Atts do
			local at = tailS + (i - 1) * step
			local e = 1e-3
			local lo, hi = math.max(at - e, 0), math.min(at + e, 1)
			local tangent = spline(slot.World, hi) - spline(slot.World, lo)
			att.WorldCFrame = alongFrame(spline(slot.World, at), tangent)
			speeds[i] = tangent.Magnitude / (hi - lo)
		end
		-- the core thins out up high and toward the tail, like a brush stroke
		-- the white core and haze fade first, leaving a thin dark ink line that erodes last
		local whiteK = math.clamp((t - wire.FadeAt + 0.25) / 0.22, 0, 1)
		-- transparency ramps along the whole trail (tail -> head), split across the segments
		local function ramp(tail, head, k)
			local a = math.clamp(tail + (1 - tail) * k, 0, 1)
			local b = math.clamp(head + (1 - head) * k, 0, 1)
			return function(i)
				local u0, u1 = (i - 1) / segments, i / segments
				local t0, t1 = a + (b - a) * u0, a + (b - a) * u1
				-- ends slightly softer: where two segments overlap at a bend this keeps the joint
				-- from flaring into a bright band, without leaving gaps on straight trails
				local function half(t)
					return 1 - (1 - t) * 0.8
				end
				return seq({
					{ 0, i == 1 and t0 or half(t0) },
					{ 0.08, t0 + (t1 - t0) * 0.08 },
					{ 0.92, t0 + (t1 - t0) * 0.92 },
					{ 1, i == segments and t1 or half(t1) },
				})
			end
		end
		local coreT = ramp(0.45, 0, whiteK)
		local inkT = NumberSequence.new(math.clamp(0.3 + 0.7 * fadeK, 0, 1))
		local hazeT = ramp(0.75, 0.4, whiteK)
		for i = 1, segments do
			for _, b in { slot.Cores[i], slot.Hazes[i], slot.Inks[i] } do
				b.CurveSize0 = speeds[i] * step / 3
				b.CurveSize1 = -speeds[i + 1] * step / 3
			end
			slot.Cores[i].Transparency = coreT(i)
			if slot.Inks[i] then
				slot.Inks[i].Transparency = inkT
			end
			slot.Hazes[i].Transparency = hazeT(i)
		end
		showWire(slot, true)
		local traveling = tipS < 0.999
		slot.Tip.Enabled = traveling
		slot.Smudge.Enabled = traveling
		if slot.Kit then
			enableKit(slot.Kit, traveling)
		end
		-- the head shines until the trail starts to fade (it rests on the target in between)
		slot.Head.Enabled = fadeK <= 0
		slot.HeadGlow.Enabled = fadeK <= 0
		return true
	end

	------------------------------------------------------------------ caster layers
	local sparks = emitter(casterFwd, {
		Texture = ASSETS.Needle,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(35, 35),
		Speed = NumberRange.new(25, 42),
		Drag = 6,
		Lifetime = NumberRange.new(0.1, 0.22),
		Size = seq({ { 0, 0.5 * sc, 0.17 * sc }, { 1, 0.1 * sc, 0.03 * sc } }),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
		Brightness = 2,
	})
	local specks = emitter(casterFwd, {
		Texture = ASSETS.Speck,
		Color = ColorSequence.new(ink),
		LightEmission = 0,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(45, 45),
		Speed = NumberRange.new(12, 28),
		Drag = 4,
		Acceleration = Vector3.new(0, -20, 0),
		Lifetime = NumberRange.new(0.2, 0.4),
		Size = sizeRange(0.12, 0.25),
		Rotation = NumberRange.new(0, 360),
	})
	local void = emitter(casterAt, { -- dark puff, then the black void frame
		Texture = ASSETS.DarkDisc,
		Color = ColorSequence.new(ink),
		LightEmission = 0,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.15),
		Size = NumberSequence.new(2 * sc),
		Transparency = seq({ { 0, 0.3 }, { 1, 1 } }),
		ZOffset = 2,
	})
	local chargeRing = emitter(casterGround, { -- chromatic ground ring, contracting
		Texture = ASSETS.ChromRing,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01),
		Lifetime = NumberRange.new(0.2),
		Size = seq({ { 0, 5 * sc }, { 0.5, 3.5 * sc }, { 1, 2 * sc } }),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } }),
		RotSpeed = NumberRange.new(200, 260),
		Brightness = 2,
	})
	local dome = emitter(casterAt, { -- white wind dome round the caster
		Texture = ASSETS.WispSphere,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.2),
		Size = seq({ { 0, 5.5 * sc }, { 1, 2.5 * sc } }),
		Transparency = seq({ { 0, 0.2 }, { 0.7, 0.4 }, { 1, 1 } }),
		Brightness = 1.5,
	})
	local casterStar = emitter(casterAt, { -- the launch flash (texture, size and lifetime set when it fires)
		Texture = ASSETS.Starburst,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.1),
		Size = seq({ { 0, 3 * sc }, { 1, 3.5 * sc } }),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		Brightness = 3,
		ZOffset = 3,
	})
	local groundStar = emitter(casterGround, { -- spiky white star lying on the floor (the charge)
		Texture = ASSETS.Starburst,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01),
		Lifetime = NumberRange.new(0.1),
		Size = seq({ { 0, 5 * sc }, { 1, 3.5 * sc } }),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		Brightness = 3,
	})
	local rays = emitter(casterAt, { -- tall prismatic curtain rays
		Texture = ASSETS.SunRays,
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.14),
		Size = seq({ { 0, 13 * sc }, { 1, 17 * sc } }),
		Squash = NumberSequence.new(0.7),
		Transparency = seq({ { 0, 0 }, { 0.5, 0.15 }, { 1, 1 } }),
		Brightness = 4,
		ZOffset = 2.5,
	})
	local blades = emitter(casterAt, { -- black-and-white speed spikes, then the crystal cluster
		Texture = ASSETS.JaggedShard,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Speed = NumberRange.new(8, 14),
		Drag = 10,
		Lifetime = NumberRange.new(0.12, 0.2),
		Size = seq({ { 0, 2.5 * sc, 0.8 * sc }, { 0.3, 4.2 * sc, 1.4 * sc }, { 1, 3.2 * sc, 1 * sc } }),
		Squash = NumberSequence.new(-0.3),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.1 }, { 1, 1 } }),
		Brightness = 2,
		ZOffset = 3,
	})
	local casterSmoke = emitter(casterAt, { -- turbulent grey-white smoke sphere
		Texture = ASSETS.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(215, 215, 220)),
		LightEmission = 0.35,
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
		Lifetime = NumberRange.new(0.25, 0.4),
		Size = seq({ { 0, 2 * sc }, { 1, 3.5 * sc } }),
		Transparency = seq({ { 0, 0.35 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
	})
	local bokeh = emitter(casterAt, { -- white dots flying out inside the shell
		Texture = ASSETS.Glow,
		Speed = NumberRange.new(12, 22),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Lifetime = NumberRange.new(0.3, 0.5),
		Size = seq({ { 0, 0.5 * sc, 0.17 * sc }, { 1, 0.25 * sc, 0.08 * sc } }),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
		Brightness = 3,
	})
	local shell = emitter(casterAt, { -- translucent dark sphere round the caster
		Texture = ASSETS.DarkDisc,
		Color = ColorSequence.new(Color3.fromRGB(30, 30, 36)),
		LightEmission = 0,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.45),
		Size = seq({ { 0, 4.5 * sc }, { 1, 5.5 * sc } }),
		Transparency = seq({ { 0, 0.55 }, { 0.6, 0.7 }, { 1, 1 } }),
		ZOffset = -2,
	})
	local flecks = emitter(casterPart, { -- rainbow diffraction flecks streaking in during the charge
		Texture = ASSETS.ChromLine,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Speed = NumberRange.new(20 * sc, 26 * sc),
		Lifetime = NumberRange.new(0.12, 0.15),
		Size = seq({ { 0, 0.9 * sc }, { 1, 0.5 * sc } }),
		Squash = NumberSequence.new(-0.5),
		Rotation = NumberRange.new(-90),
		Transparency = seq({ { 0, 0.2 }, { 1, 0.8 } }),
		Brightness = 2,
	})
	local shellArcs = emitter(casterAt, { -- thin pale arcs on the dark shell
		Texture = ASSETS.HaloThin,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.3, 0.4),
		Size = seq({ { 0, 3.5 * sc }, { 1, 4.2 * sc } }),
		Transparency = seq({ { 0, 0.75 }, { 0.6, 0.85 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		Brightness = 1,
		ZOffset = -1,
	})
	local glitchInk = emitter(casterAt, { -- black ink blotches and squiggles before the chest
		Texture = ASSETS.BlackEnergy,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.Loop,
		FlipbookFramerate = NumberRange.new(20),
		FlipbookStartRandom = true,
		Color = ColorSequence.new(ink),
		LightEmission = 0,
		Speed = NumberRange.new(1, 4),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.15, 0.3),
		Size = sizeRange(0.4 * sc, 0.8 * sc),
		Rotation = NumberRange.new(0, 360),
		ZOffset = 3,
	})
	local shards = emitter(casterPart, { -- chromatic shards drifting round the caster
		Texture = ASSETS.ChromWisp,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.2, 0.35),
		Size = seq({ { 0, 0.4 * sc, 0.12 * sc }, { 0.3, 0.7 * sc, 0.2 * sc }, { 1, 0.5 * sc, 0.15 * sc } }),
		Transparency = seq({ { 0, 0.1 }, { 0.7, 0.25 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		Brightness = 3,
		ZOffset = 1,
	})
	-- the reference's shots throw crisp sparkle stars with prismatic flares round the caster
	local prismStars = emitter(casterPart, {
		Texture = ASSETS.Star,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Speed = NumberRange.new(1, 4),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.12, 0.3),
		Size = seq({ { 0, 0.2 * sc }, { 0.3, 0.9 * sc, 0.3 * sc }, { 1, 0 } }),
		Rotation = NumberRange.new(-10, 10),
		Brightness = 6,
		ZOffset = 2,
	})
	local prismFlares = emitter(casterPart, {
		Texture = ASSETS.ChromWisp,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.15, 0.3),
		Size = seq({ { 0, 0.5 * sc, 0.15 * sc }, { 1, 0.3 * sc } }),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		Brightness = 3,
		ZOffset = 1.9,
	})

	------------------------------------------------------------------ target pre-hits
	local targetGlow = emitter(targetAt, {
		Texture = ASSETS.Glow,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.15),
		Size = seq({ { 0, 2 * sc }, { 1, 1.2 * sc } }),
		Transparency = seq({ { 0, 0 }, { 1, 1 } }),
		Brightness = 3,
		ZOffset = 1,
	})
	local targetBurst = emitter(targetAt, { -- spiky white ball engulfing the target as the wires converge
		Texture = ASSETS.Starburst,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.18),
		Size = seq({ { 0, 8 * sc }, { 0.4, 6 * sc }, { 1, 3 * sc } }),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		Brightness = 3,
		ZOffset = 3,
	})
	local targetShatter = emitter(targetAt, { -- white and prismatic glints round the target
		Texture = ASSETS.ChromWisp,
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.18, 0.3),
		Size = seq({ { 0, 0.8 * sc }, { 1, 1.2 * sc } }),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.2 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200),
		Brightness = 2,
		ZOffset = 1.5,
	})
	local targetGlints = emitter(targetPart, { -- star glints twinkling round the ink ball before the dash lands
		Texture = ASSETS.Star,
		Shape = Enum.ParticleEmitterShape.Box,
		Speed = NumberRange.new(0.2, 1),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.08, 0.16),
		Size = seq({ { 0, 0.3 * sc, 0.1 * sc }, { 0.4, 0.9 * sc, 0.3 * sc }, { 1, 0 } }),
		Rotation = NumberRange.new(-10, 10),
		Brightness = 6,
		ZOffset = 4.5,
	})
	local targetSpecks = emitter(targetAt, {
		Texture = ASSETS.Speck,
		Color = ColorSequence.new(ink),
		LightEmission = 0,
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Lifetime = NumberRange.new(0.25, 0.45),
		Size = sizeRange(0.12, 0.28),
		Rotation = NumberRange.new(0, 360),
	})
	local inkCore = emitter(targetAt, { -- dark smudge aura / black core at the target
		Texture = ASSETS.Smoke,
		Color = ColorSequence.new(ink),
		LightEmission = 0,
		Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.3, 0.5),
		Size = seq({ { 0, 1.2 * sc }, { 1, 2 * sc } }),
		Transparency = seq({ { 0, 0.35 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		ZOffset = 4,
	})

	------------------------------------------------------------------ dash
	local headAt = attachment(base, CFrame.fromMatrix(caster + UP * 2.5 * sc, right, -dashDir))
	-- the head, as in the reference: a flickering spiky white ball with a white splash fanned
	-- back off it, a dark smoke wedge with chromatic slivers trailing it and black debris
	-- (shotHead), a thin bright line back to the caster over a soft white haze, and glowing
	-- white orbs left along the path over the rainbow ground streak
	local headBall = emitter(headAt, {
		Texture = ASSETS.Starburst,
		LockedToPart = true,
		Rate = 70,
		Enabled = false,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.05, 0.08),
		Size = seq({ { 0, 1.1 * sc, 0.2 * sc }, { 1, 1.5 * sc, 0.2 * sc } }),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		Brightness = 4,
		ZOffset = 1.6,
		TimeScale = ctx.TimeScale,
	})
	local headCore = emitter(headAt, {
		Texture = ASSETS.Glow,
		LockedToPart = true,
		Rate = 40,
		Enabled = false,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.06),
		Size = NumberSequence.new(1.5 * sc),
		Transparency = seq({ { 0, 0.3 }, { 1, 1 } }),
		Brightness = 3,
		ZOffset = 1.4,
		TimeScale = ctx.TimeScale,
	})
	-- EmissionDirection Top = the attachment's +Y, which headAt points back at the caster
	local dashKit = shotHead(headAt, Enum.NormalId.Top, sc)
	local headFlares = emitter(headAt, { -- small prismatic flares thrown off the head
		Texture = ASSETS.ChromWisp,
		Rate = 30,
		Enabled = false,
		Speed = NumberRange.new(2 * sc, 6 * sc),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Lifetime = NumberRange.new(0.2, 0.35),
		Size = seq({ { 0, 0.45 * sc, 0.15 * sc }, { 1, 0.2 * sc } }),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		Brightness = 4,
		ZOffset = 1.2,
		TimeScale = ctx.TimeScale,
	})
	local pathOrbs = emitter(headAt, { -- glowing white orbs left hanging along the path
		Texture = ASSETS.WispSphere,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Rate = 16,
		Enabled = false,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.3, 0.45),
		Size = seq({ { 0, 1 * sc }, { 0.4, 1.8 * sc, 0.3 * sc }, { 1, 1.5 * sc } }),
		Transparency = seq({ { 0, 0.2 }, { 0.6, 0.35 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		Brightness = 2.5,
		ZOffset = 0.3,
		TimeScale = ctx.TimeScale,
	})
	local streakTail = attachment(base, CFrame.new(caster))
	local streakHead = attachment(base, CFrame.new(caster))
	local dashLine = beam(streakHead, streakTail, { -- thin bright line (no texture: solid)
		Color = ColorSequence.new(LINE),
		Brightness = 4,
		Segments = 2,
		Width0 = 0,
		Width1 = 0,
		ZOffset = 1,
		Enabled = false,
	})
	local dashHaze = beam(streakHead, streakTail, { -- the soft white streak round it
		Texture = ASSETS.SoftTrail,
		TextureMode = Enum.TextureMode.Wrap,
		TextureLength = 6 * sc,
		TextureSpeed = -0.8,
		Color = ColorSequence.new(p.Color),
		LightEmission = 0.6,
		Brightness = 1.5,
		Segments = 2,
		Width0 = 0,
		Width1 = 0,
		ZOffset = 0.9,
		Enabled = false,
	})
	local tunnelAt = attachment(base, CFrame.fromMatrix(caster + UP * 3, right, dashDir))
	local tunnelRing = emitter(tunnelAt, { -- vertical rings standing across the dash path
		Texture = ASSETS.BandRing,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01),
		Lifetime = NumberRange.new(0.16),
		Size = seq({ { 0, 4 * sc }, { 1, 1.5 * sc } }),
		Transparency = seq({ { 0, 0.3 }, { 1, 1 } }),
		Brightness = 1.5,
	})
	-- the rainbow ground streak: a flat beam (width along the attachments' Y = across the path)
	local railBack = attachment(base, CFrame.fromMatrix(caster - dashDir * 4 + UP * 0.08, dashDir, right))
	local railFront = attachment(base, CFrame.fromMatrix(target + UP * 0.08, dashDir, right))
	local rail = beam(railBack, railFront, {
		Texture = ASSETS.RainbowStreak,
		TextureMode = Enum.TextureMode.Wrap,
		TextureLength = 12,
		FaceCamera = false,
		Segments = 10,
		Width0 = 0,
		Width1 = 0,
		Brightness = 2,
		Enabled = false,
	})
	local railCore = beam(railBack, railFront, { -- the white centre between the rainbow rails
		Texture = ASSETS.SoftTrail,
		TextureMode = Enum.TextureMode.Wrap,
		TextureLength = 8,
		FaceCamera = false,
		Segments = 10,
		Width0 = 0,
		Width1 = 0,
		Brightness = 3,
		ZOffset = 0.1,
		Enabled = false,
	})

	------------------------------------------------------------------ impact
	local function flashEmitter(color, size, brightness)
		return emitter(impactAt, {
			Texture = ASSETS.ImpactFlash,
			Color = ColorSequence.new(color),
			Speed = NumberRange.new(0),
			Lifetime = NumberRange.new(0.12),
			Size = seq({ { 0, size * 0.75 }, { 0.25, size }, { 1, size * 1.05 } }),
			Transparency = seq({ { 0, 0 }, { 0.5, 0.05 }, { 1, 1 } }),
			Rotation = NumberRange.new(-6, 6),
			Brightness = brightness,
			ZOffset = 4,
		})
	end
	local flashRed = flashEmitter(p.FringeRed, 11.6 * s, 0.7)
	local flashBlue = flashEmitter(p.FringeBlue, 11.3 * s, 0.7)
	local flashWhite = flashEmitter(p.Color, 10.8 * s, 2)
	-- the wider, fainter V flare 0.1 s later: its own emitters (Size changes resize live particles)
	local wingBlue = flashEmitter(p.FringeBlue, 9.5 * s, 1.3)
	local wingWhite = flashEmitter(p.Color, 9 * s, 2)
	for _, e in { wingBlue, wingWhite } do
		e.Squash = NumberSequence.new(-0.25)
		e.Transparency = seq({ { 0, 0.55 }, { 1, 1 } })
	end

	local pillarTop = attachment(base, CFrame.new(target + UP * 55 * s))
	local pillarBottom = attachment(base, CFrame.new(target))
	local pillarCore = beam(pillarTop, pillarBottom, {
		Texture = ASSETS.PillarCore,
		Color = ColorSequence.new(p.Color),
		Brightness = 5,
		Width0 = 0,
		Width1 = 0,
		Segments = 12,
		Transparency = seq({ { 0, 0.75 }, { 0.6, 0.5 }, { 1, 0.4 } }),
		Enabled = false,
	})
	local pillarLines = beam(pillarTop, pillarBottom, {
		Texture = ASSETS.PillarLines,
		TextureMode = Enum.TextureMode.Wrap,
		TextureLength = 18,
		TextureSpeed = 3,
		Color = ColorSequence.new(p.Color),
		Brightness = 2,
		Width0 = 0,
		Width1 = 0,
		Segments = 12,
		Enabled = false,
	})
	local pillarDark = beam(pillarTop, pillarBottom, {
		Texture = ASSETS.PillarDark,
		TextureMode = Enum.TextureMode.Wrap,
		TextureLength = 31,
		TextureSpeed = 7,
		Color = ColorSequence.new(ink),
		LightEmission = 0,
		Width0 = 0,
		Width1 = 0,
		Segments = 12,
		Transparency = NumberSequence.new(0.35),
		ZOffset = -1,
		Enabled = false,
	})

	local groundWave = emitter(groundAt, { -- dark shockwave racing out, then the dark ground ring
		Texture = ASSETS.SmokeRing,
		Color = ColorSequence.new(Color3.fromRGB(30, 30, 36)),
		LightEmission = 0,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01),
		Lifetime = NumberRange.new(2.1),
		Size = seq({ { 0, 3 * s }, { 0.04, 19 * s }, { 0.5, 15 * s }, { 1, 12 * s } }),
		Transparency = seq({ { 0, 0.1 }, { 0.05, 0.25 }, { 0.6, 0.6 }, { 1, 1 } }),
		RotSpeed = NumberRange.new(15, 25),
	})
	local function ringEmitter(parent, props)
		local e = emitter(parent, {
			Texture = ASSETS.NeonRing,
			Color = ColorSequence.new(p.Color),
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			EmissionDirection = Enum.NormalId.Top,
			Speed = NumberRange.new(0.01),
			Brightness = 2,
		})
		for key, value in props do
			e[key] = value
		end
		return e
	end
	-- ring radius = size * 0.75 for thick ring 3 (NeonRing), size * 0.86 for HaloThin
	local ringBase = ringEmitter(ringLowAt, { -- crisp base ring, contracting
		Lifetime = NumberRange.new(1),
		Size = seq({ { 0, 7 * s }, { 0.08, 9 * s }, { 0.5, 7.5 * s }, { 1, 4.5 * s } }),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.15 }, { 1, 1 } }),
	})
	local ringBaseOuter = ringEmitter(ringLowAt, { -- fainter outer base ring
		Texture = ASSETS.BandRing,
		Lifetime = NumberRange.new(0.45),
		Size = seq({ { 0, 12 * s }, { 1, 15 * s } }),
		Transparency = seq({ { 0, 0.45 }, { 1, 1 } }),
	})
	local ringPulse = ringEmitter(ringLowAt, { -- base ring pulse 2: expands to a hairline
		Lifetime = NumberRange.new(0.2),
		Size = seq({ { 0, 6 * s }, { 0.4, 9 * s }, { 1, 12.5 * s } }),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.2 }, { 1, 1 } }),
		Brightness = 3,
	})
	local ringUp = ringEmitter(ringHighAt, { -- upper halo, rising
		Texture = ASSETS.HaloThin,
		Brightness = 3.5,
		Speed = NumberRange.new(10 * s),
		Lifetime = NumberRange.new(0.5),
		Size = seq({ { 0, 5 * s }, { 0.2, 6.3 * s }, { 1, 7.2 * s } }),
		Transparency = seq({ { 0, 0.05 }, { 0.6, 0.15 }, { 1, 1 } }),
	})
	local ringUpOuter = ringEmitter(ringHighAt, { -- thinner, wider halo above it
		Texture = ASSETS.HaloThin,
		Brightness = 2.5,
		Speed = NumberRange.new(11 * s),
		Lifetime = NumberRange.new(0.45),
		Size = seq({ { 0, 7.8 * s }, { 1, 9.4 * s } }),
		Transparency = seq({ { 0, 0.3 }, { 0.6, 0.45 }, { 1, 1 } }),
	})

	local function spikeFan(at, lean)
		return emitter(at, { -- white crystal blades fanning out of the impact
			Texture = ASSETS.JaggedShard,
			Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
			Speed = NumberRange.new(0.5, 2),
			SpreadAngle = Vector2.new(180, 180),
			Lifetime = NumberRange.new(0.15, 0.32),
			Size = seq({ { 0, 1.5 * s, 0.5 * s }, { 0.15, 5 * s, 1.6 * s }, { 0.7, 4.5 * s, 1.5 * s }, { 1, 0 } }),
			Transparency = seq({ { 0, 0.1 }, { 0.7, 0.25 }, { 1, 1 } }),
			Rotation = lean,
			-- solid, not additive: overlapping additive spikes add up to a white blob
			LightEmission = 0.25,
			Brightness = 2.5,
			ZOffset = 1,
			TimeScale = ctx.TimeScale,
		})
	end
	-- positive Rotation turns counter-clockwise: the left fan leans left, the right fan right
	local spikesLeft = spikeFan(spikeLeft, NumberRange.new(5, 70))
	local spikesRight = spikeFan(spikeRight, NumberRange.new(-70, -5))
	local chromSpikes = emitter(spikePart, { -- rainbow spikes and tips
		Texture = ASSETS.ChromLine,
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		Speed = NumberRange.new(0.5, 2),
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.12, 0.25),
		Size = seq({ { 0, 2 * s }, { 0.2, 4 * s }, { 1, 2.5 * s } }),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } }),
		Rotation = NumberRange.new(-40, 40),
		Brightness = 2.5,
		ZOffset = 1.5,
		TimeScale = ctx.TimeScale,
	})
	local blobs = emitter(spikePart, { -- prismatic patches flickering in the burst
		Texture = ASSETS.ChromWisp2,
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Speed = NumberRange.new(2, 6),
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.12, 0.22),
		Size = seq({ { 0, 1.5 * s }, { 0.3, 2.5 * s }, { 1, 2 * s } }),
		Transparency = seq({ { 0, 0.1 }, { 0.7, 0.3 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		Brightness = 2,
		ZOffset = 2,
	})
	local glitch = emitter(glitchPart, { -- black-edged RGB-split zigzag bolts (colour baked)
		Texture = ASSETS.RgbBolt,
		Shape = Enum.ParticleEmitterShape.Box,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.1, 0.18),
		Size = sizeRange(3 * s, 5 * s),
		Transparency = seq({ { 0, 0 }, { 0.7, 0 }, { 1, 1 } }),
		Rotation = NumberRange.new(-70, 70),
		LightEmission = 0,
		Brightness = 1.5,
		ZOffset = 3,
	})
	-- 4-point star flashes popping all over the burn, a few big ones
	local starFlash = emitter(glitchPart, {
		Texture = ASSETS.Star,
		Shape = Enum.ParticleEmitterShape.Box,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.06, 0.12),
		Size = seq({ { 0, 0.5 * s, 0.2 * s }, { 0.3, 2.2 * s, 0.9 * s }, { 1, 0 } }),
		Rotation = NumberRange.new(-10, 10),
		Brightness = 8,
		ZOffset = 4,
	})
	local bigStar = emitter(flareAt, {
		Texture = ASSETS.Star,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.14),
		Size = seq({ { 0, 2 * s }, { 0.25, 9 * s }, { 1, 0 } }),
		Brightness = 10,
		ZOffset = 6,
	})
	local flare = emitter(flareAt, { -- horizontal chromatic blade flares (moved per flare)
		Texture = ASSETS.LineFlare,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.12),
		Size = seq({ { 0, 12 * s }, { 0.3, 16 * s }, { 1, 14 * s } }),
		Transparency = seq({ { 0, 0 }, { 0.5, 0.1 }, { 1, 1 } }),
		Brightness = 3,
		ZOffset = 5,
	})
	local flareVAt = attachment(base, CFrame.new(target + UP * 7 * s - right * 3 * s))
	local flareV = emitter(flareVAt, { -- the vertical flare beside the pillar
		Texture = ASSETS.LineFlare,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.12),
		Size = seq({ { 0, 6 * s }, { 0.3, 8 * s }, { 1, 7 * s } }),
		Transparency = seq({ { 0, 0 }, { 0.5, 0.1 }, { 1, 1 } }),
		Rotation = NumberRange.new(90),
		Brightness = 3,
		ZOffset = 5,
	})
	local cross = emitter(crossAt, { -- the finale's 4-point cross, shrinking to a dot
		Texture = ASSETS.Star,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.15),
		Size = seq({ { 0, 12 * s }, { 0.33, 2.8 * s }, { 0.66, 0.5 * s }, { 1, 0 } }),
		Transparency = seq({ { 0, 0 }, { 0.66, 0 }, { 1, 1 } }),
		Brightness = 4,
		ZOffset = 5,
	})
	local bar = emitter(crossAt, { -- thick soft white bars of the finale cross (emitted twice)
		Texture = ASSETS.Glow,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.1),
		Size = seq({ { 0, 16 * s }, { 0.5, 10 * s }, { 1, 2 * s } }),
		Squash = NumberSequence.new(-0.93),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } }),
		Brightness = 4,
		ZOffset = 5,
	})
	local barV = emitter(crossAt, { -- the cross's shorter vertical bar
		Texture = ASSETS.Glow,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.1),
		Size = seq({ { 0, 5 * s }, { 0.5, 3.5 * s }, { 1, 1 * s } }),
		Squash = NumberSequence.new(-0.93),
		Transparency = seq({ { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } }),
		Rotation = NumberRange.new(90),
		Brightness = 4,
		ZOffset = 5,
	})
	local smoke = emitter(smokePart, { -- grey-white smoke spreading across the floor
		Texture = ASSETS.Smoke,
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Color = ColorSequence.new(p.SmokeColor),
		LightEmission = 0.25,
		Rate = p.SmokeRate,
		Enabled = false,
		Speed = NumberRange.new(1, 3),
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(1, 1.4),
		Size = seq({ { 0, 3 * s, 1 * s }, { 1, 6 * s, 2 * s } }),
		Squash = NumberSequence.new(-0.5), -- flat, hugging the floor
		Transparency = seq({ { 0, 1 }, { 0.15, 0.72 }, { 0.6, 0.8 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
		TimeScale = ctx.TimeScale,
	})
	local plumes = emitter(plumePart, { -- crown of arched smoke plumes / wind wisps
		Texture = ASSETS.SmokeHook,
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		Color = ColorSequence.new(p.SmokeColor:Lerp(WHITE, 0.4)),
		LightEmission = 0.4,
		Speed = NumberRange.new(1, 2.5),
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.8, 1.1),
		Size = seq({ { 0, 2.6 * s, 0.6 * s }, { 1, 3.2 * s, 0.7 * s } }),
		Squash = NumberSequence.new(0.15), -- the hook texture is 1:2 tall; wide, soft sheets
		Transparency = seq({ { 0, 1 }, { 0.15, 0.45 }, { 0.6, 0.6 }, { 1, 1 } }),
		Rotation = NumberRange.new(-12, 12),
	})
	local leaves = emitter(groundAt, {
		Texture = ASSETS.Leaf,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.Loop,
		FlipbookFramerate = NumberRange.new(16, 24),
		FlipbookStartRandom = true,
		LightEmission = 0,
		LightInfluence = 0.3,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(70, 70),
		Speed = NumberRange.new(12 * s, 22 * s),
		Drag = 3,
		Acceleration = Vector3.new(0, -6 * s, 0),
		Lifetime = NumberRange.new(0.9, 1.4),
		Size = sizeRange(0.6 * s, 1 * s),
		Transparency = seq({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200),
	})
	local rocks = emitter(groundAt, {
		Texture = ASSETS.Rocks,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookFramerate = NumberRange.new(0),
		FlipbookStartRandom = true,
		Color = ColorSequence.new(Color3.fromRGB(110, 112, 118)),
		LightEmission = 0,
		LightInfluence = 0.4,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(60, 60),
		Speed = NumberRange.new(10 * s, 18 * s),
		Drag = 3,
		Acceleration = Vector3.new(0, -3 * s, 0),
		Lifetime = NumberRange.new(1.2, 1.7),
		Size = sizeRange(0.35 * s, 0.8 * s),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
	})
	local puffs = emitter(groundAt, { -- lumpy opaque warm-grey puffs bursting outward
		Texture = ASSETS.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(200, 196, 190)),
		LightEmission = 0,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(80, 80),
		Speed = NumberRange.new(10 * s, 16 * s),
		Drag = 4,
		Lifetime = NumberRange.new(0.5, 0.7),
		Size = seq({ { 0, 2.5 * s, 0.8 * s }, { 1, 4.5 * s, 1.5 * s } }),
		Transparency = seq({ { 0, 0.15 }, { 0.6, 0.35 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
	})
	local rainbowRays = emitter(groundAt, { -- long rainbow lens-flare streaks shooting out low
		Texture = ASSETS.ChromLine,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(80, 80),
		Speed = NumberRange.new(35 * s, 55 * s),
		Drag = 10,
		Lifetime = NumberRange.new(0.12, 0.2),
		Size = seq({ { 0, 1.2 * s }, { 1, 0.6 * s } }),
		Squash = NumberSequence.new(-1.2), -- long along the flight
		Rotation = NumberRange.new(-90),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
		Brightness = 3,
		ZOffset = 2,
	})
	local inkClaws = emitter(impactAt, { -- black ink claw slashes framing the crown
		Texture = ASSETS.DashSwirl,
		Color = ColorSequence.new(ink),
		LightEmission = 0,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.18, 0.26),
		Size = sizeRange(3 * s, 4.5 * s),
		Rotation = NumberRange.new(100, 200),
		Transparency = seq({ { 0, 0.1 }, { 0.7, 0.2 }, { 1, 1 } }),
		ZOffset = 5,
	})
	local impactRays = emitter(impactAt, { -- broad soft light rays fanning out of the flash
		Texture = ASSETS.SunRays,
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.25),
		Size = seq({ { 0, 12 * s }, { 1, 16 * s } }),
		Transparency = seq({ { 0, 0.2 }, { 0.5, 0.4 }, { 1, 1 } }),
		Brightness = 2,
		ZOffset = 3,
	})
	local windRings = emitter(groundAt, { -- swirling wind rings expanding across the floor
		Texture = ASSETS.SmokeRing,
		Color = ColorSequence.new(Color3.fromRGB(225, 225, 230)),
		LightEmission = 0.4,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01),
		Lifetime = NumberRange.new(0.7, 0.9),
		Size = seq({ { 0, 8 * s }, { 1, 20 * s } }),
		Transparency = seq({ { 0, 0.4 }, { 0.5, 0.6 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
	})
	local coreStar = emitter(impactAt, { -- white-hot spiky core: very bright, very short (design.md 4)
		Texture = ASSETS.Starburst,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.07),
		Size = seq({ { 0, 4 * s }, { 0.3, 7 * s }, { 1, 7.5 * s } }),
		Transparency = seq({ { 0, 0 }, { 0.5, 0 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		Brightness = 25,
		ZOffset = 6,
	})
	local blastStreaks = emitter(impactAt, { -- white streaks blasted out of the impact
		Texture = ASSETS.Needle,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		SpreadAngle = Vector2.new(180, 180),
		Speed = NumberRange.new(55 * s, 90 * s),
		Drag = 9,
		Lifetime = NumberRange.new(0.18, 0.35),
		Size = seq({ { 0, 1.6 * s, 0.5 * s }, { 1, 0.3 * s, 0.1 * s } }),
		Squash = seq({ { 0, 1.5 }, { 1, 0.5 } }),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
		Brightness = 4,
		ZOffset = 3,
	})
	local groundFlash = emitter(groundAt, { -- crisp white ring racing out across the floor
		Texture = ASSETS.HaloThin,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01),
		Lifetime = NumberRange.new(0.3),
		Size = seq({ { 0, 2 * s }, { 0.4, 15 * s }, { 1, 20 * s } }),
		Transparency = seq({ { 0, 0 }, { 0.5, 0.3 }, { 1, 1 } }),
		Brightness = 4,
	})
	local motes = emitter(spikePart, { -- white glints rising through the burn
		Texture = ASSETS.Sparkle,
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top,
		Rate = p.MoteRate,
		Enabled = false,
		Speed = NumberRange.new(6 * s, 14 * s),
		Drag = 1.5,
		Lifetime = NumberRange.new(0.5, 0.9),
		Size = seq({ { 0, 0.5 * s, 0.17 * s }, { 1, 0 } }),
		Rotation = NumberRange.new(0, 90),
		Brightness = 4,
		TimeScale = ctx.TimeScale,
	})
	local sparkles = emitter(spikePart, { -- small white glints in the burst
		Texture = ASSETS.Sparkle,
		Shape = Enum.ParticleEmitterShape.Disc,
		Speed = NumberRange.new(3, 9),
		EmissionDirection = Enum.NormalId.Top,
		Drag = 2,
		Lifetime = NumberRange.new(0.3, 0.6),
		Size = seq({ { 0, 0.5 * s, 0.17 * s }, { 1, 0 } }),
		Rotation = NumberRange.new(0, 90),
		Brightness = 3,
	})

	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = math.min(p.LightRange * s, 20) -- budget: Range 20 at most
	light.Brightness = 0
	light.Shadows = false
	light.Parent = impactAt

	------------------------------------------------------------------ vignette
	local camera = workspace.CurrentCamera
	local vignettePart, vigLeft, vigRight, vigWash
	if p.Vignette and camera then
		vignettePart = ctx.Anchor(camera.CFrame)
		local function edge(color)
			local att = Instance.new("Attachment")
			att.Parent = vignettePart
			local e = emitter(att, {
				Texture = ASSETS.Glow,
				Color = ColorSequence.new(color),
				LockedToPart = true,
				Speed = NumberRange.new(0),
				Lifetime = NumberRange.new(30),
				Size = NumberSequence.new(1),
				Transparency = NumberSequence.new(1),
				Brightness = 1,
			})
			ctx.Emit(e, 1)
			return att, e
		end
		local leftAtt, leftE = edge(p.VignetteLeft)
		local rightAtt, rightE = edge(p.VignetteRight)
		local washAtt, washE = edge(Color3.fromRGB(200, 200, 205)) -- whole-screen wash on the big flashes
		vigLeft = { Att = leftAtt, E = leftE, Side = -1 }
		vigRight = { Att = rightAtt, E = rightE, Side = 1 }
		vigWash = { Att = washAtt, E = washE, Side = 0 }
	end
	local washKeys = {
		{ tLaunch - 0.01, 0 }, { tLaunch, 0.35 }, { tLaunch + 0.1, 0 },
		{ tImpact - 0.01, 0 }, { tImpact, 0.6 }, { tImpact + 0.12, 0.35 }, { tImpact + 0.3, 0 },
	}
	local vignetteKeys = {
		{ tLaunch - 0.01, 0 }, { tLaunch, 1 }, { tLaunch + 0.12, 0.8 }, { tLaunch + 0.3, 0.15 },
		{ tImpact - 0.02, 0.15 }, { tImpact, 1 }, { tImpact + 0.08, 0.7 }, { tImpact + 0.2, 0 },
	}

	------------------------------------------------------------------ events
	local events = {}
	local function at(time, fn)
		table.insert(events, { time, fn })
	end
	local function burst(time, e, n)
		at(time, function()
			ctx.Emit(e, n)
		end)
	end

	-- opening sparks, salvo 2 sparks
	burst(0.12, sparks, p.SparkCount)
	at(0.01, function() -- a faint wind shell and a couple of rainbow glints at the caster
		dome.Size = seq({ { 0, 2 * sc }, { 1, 4.5 * sc } })
		dome.Transparency = seq({ { 0, 0.55 }, { 1, 1 } })
		dome.Lifetime = NumberRange.new(0.15)
		ctx.Emit(dome, 1)
		ctx.Emit(shards, 2)
	end)
	burst(0.5, shards, 2)
	burst(0, specks, 10)
	burst(0.05, void, 1)
	burst(0.5, sparks, math.ceil(p.SparkCount * 0.6))
	for _, time in { 0.12, 0.52 } do -- V-shaped wings of white streaky cones as each salvo fires
		at(time, function()
			blades.EmissionDirection = Enum.NormalId.Top
			blades.SpreadAngle = Vector2.new(45, 45)
			ctx.Emit(blades, 2)
			ctx.Emit(casterSmoke, 2)
		end)
	end
	burst(0.46, bokeh, 14) -- a cloud of white diamond sparkles before the second salvo
	for time = 1.18, 1.82, 0.05 do -- glints twinkle round the target until the dash drills in
		burst(time, targetGlints, 3)
	end
	for i = 0, 3 do -- glitter spraying off the caster while the low streak runs
		burst(0.2 + i * 0.08, bokeh, math.ceil(p.BokehCount * 0.2))
		burst(0.22 + i * 0.08, prismStars, 3)
	end
	burst(0.5, targetShatter, 1)
	-- salvo 1 hits the target
	at(0.6, function()
		targetGlow.Size = seq({ { 0, 1.6 * sc }, { 1, 2.2 * sc } })
		ctx.Emit(targetGlow, 1)
		ctx.Emit(targetShatter, 2)
	end)
	burst(0.66, targetSpecks, math.ceil(p.SpeckCount * 0.6))
	burst(0.7, inkCore, 4)
	burst(0.85, inkCore, 3)
	-- convergence flash at the target, chromatic ring + wind dome at the caster
	at(tCharge, function()
		targetGlow.Size = seq({ { 0, 10 * sc }, { 0.4, 7 * sc }, { 1, 4 * sc } })
		targetGlow.Lifetime = NumberRange.new(0.2)
		ctx.Emit(targetGlow, 1)
		ctx.Emit(targetBurst, 1)
		ctx.Emit(chargeRing, 1)
		dome.Size = seq({ { 0, 5.5 * sc }, { 1, 2.5 * sc } })
		dome.Transparency = seq({ { 0, 0.2 }, { 0.7, 0.4 }, { 1, 1 } })
		dome.Lifetime = NumberRange.new(0.2)
		ctx.Emit(dome, 1)
		ctx.Emit(flecks, 14)
	end)
	at(tCharge + 0.05, function()
		flareAt.WorldCFrame = CFrame.new(target + UP * 3)
		flare.Size = seq({ { 0, 3 * sc }, { 0.3, 4 * sc }, { 1, 3 * sc } })
		ctx.Emit(flare, 1)
		ctx.Emit(groundStar, 1)
	end)
	at(tCharge + 0.1, function()
		ctx.Emit(targetShatter, 8)
		ctx.Emit(targetSpecks, math.ceil(p.SpeckCount * 0.6))
		ctx.Emit(inkCore, 3)
		ctx.Emit(groundStar, 1)
		ctx.Emit(flecks, 8)
	end)
	for time = tCharge + 0.15, tImpact - 0.05, 0.06 do -- the glass cluster keeps sparkling
		burst(time, targetShatter, 3)
	end
	-- black void frame
	at(tVoid, function()
		void.Size = seq({ { 0, 6 * sc }, { 1, 7 * sc } })
		void.Transparency = seq({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } })
		void.Lifetime = NumberRange.new(0.04)
		ctx.Emit(void, 1)
	end)
	-- launch starburst, prismatic rays, speed spikes, dash starts
	at(tLaunch, function()
		casterStar.Texture = ASSETS.ImpactFlash -- a soft white mass, not a needle star
		casterStar.Size = seq({ { 0, 4 * sc }, { 0.3, 5.5 * sc }, { 1, 6 * sc } })
		casterStar.Lifetime = NumberRange.new(0.08)
		ctx.Emit(casterStar, 1)
		ctx.Emit(rays, 1)
		blades.EmissionDirection = Enum.NormalId.Bottom
		blades.SpreadAngle = Vector2.new(25, 25)
		ctx.Emit(blades, 8)
		ctx.Emit(sparks, math.ceil(p.SparkCount * 0.75))
	end)
	at(tLaunch + 0.05, function() -- crystal cluster round the smoke sphere
		blades.EmissionDirection = Enum.NormalId.Top
		blades.SpreadAngle = Vector2.new(180, 180)
		ctx.Emit(blades, 11)
		ctx.Emit(casterSmoke, 8)
	end)
	burst(tLaunch + 0.1, bokeh, p.BokehCount)
	burst(tLaunch + 0.1, shell, 1)
	burst(tLaunch + 0.12, shellArcs, 3)
	for i = 0, 3 do
		burst(tLaunch + 0.2 + i * 0.07, glitchInk, 1)
		burst(tLaunch + 0.2 + i * 0.07, specks, 4)
	end
	for i = 0, 4 do
		burst(tLaunch + 0.25 + i * 0.05, shards, 4)
		burst(tLaunch + 0.25 + i * 0.05, prismStars, 3)
	end
	at(tLaunch + 0.02, function()
		ctx.Emit(prismStars, 10)
		ctx.Emit(prismFlares, 6)
	end)
	-- each salvo: a spray of sparkle stars and prismatic flares round the caster
	for _, time in { 0.12, 0.52 } do
		at(time + 0.01, function()
			ctx.Emit(prismStars, 8)
			ctx.Emit(prismFlares, 4)
		end)
	end
	-- tunnel rings along the dash corridor (~9 and ~18 studs out at the default distance)
	for i, along in { 0.28, 0.57 } do
		at(tLaunch + 0.04 + i * 0.05, function()
			tunnelAt.WorldCFrame = CFrame.fromMatrix(caster + toTarget * along + UP * 3 * sc, right, dashDir)
		end)
		burst(tLaunch + 0.06 + i * 0.05, tunnelRing, 1)
	end

	-- impact
	at(tImpact, function()
		-- solid white body under the spikes (the target glow, blown up)
		targetGlow.Size = seq({ { 0, 6 * s }, { 0.5, 4 * s }, { 1, 2.5 * s } })
		targetGlow.Lifetime = NumberRange.new(0.15)
		ctx.Emit(targetGlow, 1)
		ctx.Emit(flashRed, 1)
		ctx.Emit(flashBlue, 1)
		ctx.Emit(flashWhite, 1)
		ctx.Emit(coreStar, 1)
		ctx.Emit(blastStreaks, p.StreakCount)
		ctx.Emit(groundFlash, 1)
		inkCore.Size = seq({ { 0, 1.5 * s }, { 1, 2.2 * s } })
		inkCore.Lifetime = NumberRange.new(0.35, 0.5)
		ctx.Emit(inkCore, 6)
	end)
	burst(tImpact + 0.05, groundWave, 1)
	at(tImpact + 0.1, function() -- the wide V flare as the pillar forms
		ctx.Emit(wingWhite, 1)
		ctx.Emit(wingBlue, 1)
		ctx.Emit(leaves, p.LeafCount)
		ctx.Emit(rocks, p.RockCount)
		ctx.Emit(puffs, p.PuffCount)
		ctx.Emit(targetSpecks, p.SpeckCount) -- black shrapnel
		ctx.Emit(sparkles, 30)
	end)
	at(tImpact + 0.15, function()
		ctx.Emit(ringBase, 1)
		ctx.Emit(ringBaseOuter, 1)
		ctx.Emit(chromSpikes, 10)
	end)
	-- crystal surges: big waves of spikes on top of the steady burn, each with a burst of streaks
	for _, time in { tImpact + 0.06, tImpact + 0.45, tImpact + 0.85 } do
		burst(time, spikesLeft, 6)
		burst(time + 0.01, spikesRight, 6)
		burst(time + 0.02, blastStreaks, math.ceil(p.StreakCount / 3))
	end
	-- crystal spikes, rainbow tips and prismatic patches: bursts every ~0.07 s
	local burn = tImpact + 0.12
	while burn < tFinale - 0.15 do
		local n = math.max(1, math.floor(p.SpikeRate * 0.07 + 0.5))
		burst(burn, spikesLeft, math.ceil(n / 2))
		burst(burn + 0.01, spikesRight, math.ceil(n / 2))
		burst(burn + 0.03, chromSpikes, math.max(1, n))
		if burn < tFinale - 0.4 then
			burst(burn + 0.02, blobs, 2)
		end
		burn += 0.07
	end
	for i = 0, 5 do -- dark ink core at the target's feet while it burns
		burst(tImpact + 0.12 + i * 0.12, inkCore, 2)
	end
	-- glitch ribbons
	local burnLen = tFinale - tImpact
	for i = 0, 13 do -- RGB glitch bolts flicker through the burn, often in pairs
		local time = tImpact + 0.15 + i * (burnLen - 0.3) / 13
		burst(time, glitch, i % 3 == 0 and 2 or 1)
	end
	for i, wire in WIRES do -- a big star flash at a projectile's apex
		if wire.Glint then
			at(wire.Glint, function()
				local tip = wireSlots[i].Atts[#wireSlots[i].Atts]
				flareAt.WorldCFrame = CFrame.new(tip.WorldPosition)
				bigStar.Size = seq({ { 0, 1 * sc }, { 0.25, 5 * sc }, { 1, 0 } })
				ctx.Emit(bigStar, 1)
			end)
		end
	end
	for _, dt in { 0.3, 0.5, 0.9, 1.35 } do
		burst(tImpact + dt, rainbowRays, 4)
	end
	burst(tImpact + 0.13, inkClaws, 3)
	burst(tImpact + 0.55, inkClaws, 2)
	local starT = tImpact + 0.05
	while starT < tFinale - 0.05 do -- star flashes every ~0.06 s, more early
		burst(starT, starFlash, starT < tImpact + 0.6 and 3 or 2)
		starT += 0.06
	end
	for i, frac in { 0.05, 0.28, 0.5, 0.72, 0.9 } do -- big cross stars
		at(tImpact + frac * burnLen, function()
			bigStar.Size = seq({ { 0, 2 * s }, { 0.25, 9 * s }, { 1, 0 } })
			flareAt.WorldCFrame = CFrame.new(target + UP * (4 + i) * s + right * ((i % 2) * 2 - 1) * 2 * s)
			ctx.Emit(bigStar, 1)
		end)
	end
	-- upper halo waves
	burst(tImpact + 0.2, ringUp, 1)
	burst(tImpact + 0.55, ringUp, 1)
	burst(tImpact + 0.6, ringUpOuter, 1)
	burst(tImpact + 0.25, ringUpOuter, 1)
	burst(tImpact + 0.9, ringUp, 1)
	burst(tImpact + 1.3, ringUp, 1)
	burst(tImpact + 1.35, ringUpOuter, 1)
	burst(tImpact + 1.25, ringPulse, 1)
	burst(tImpact + 0.95, ringUpOuter, 1)
	burst(tFinale - 0.25, ringUp, 1)
	burst(tFinale - 0.2, ringUpOuter, 1)
	-- base ring pulse 2
	burst(tFinale - 0.2, ringPulse, 1)
	-- horizontal blade flares (and a vertical rainbow one with the second)
	at(tImpact + 0.42, function()
		flareAt.WorldCFrame = CFrame.new(target + UP * 5.5 * s)
		flare.Size = seq({ { 0, 12 * s }, { 0.3, 16 * s }, { 1, 14 * s } })
		flare.Rotation = NumberRange.new(0)
		ctx.Emit(flare, 1)
	end)
	at(tImpact + 0.8, function()
		flareAt.WorldCFrame = CFrame.new(target + UP * 7.5 * s)
		ctx.Emit(flare, 1)
		ctx.Emit(sparkles, 8)
	end)
	burst(tImpact + 0.82, flareV, 1)
	-- finale cross
	at(tFinale, function()
		ctx.Emit(cross, 1)
		ctx.Emit(bar, 1)
		ctx.Emit(barV, 1)
		ctx.Emit(groundFlash, 1)
		ctx.Emit(blastStreaks, math.ceil(p.StreakCount / 2))
		ctx.Emit(sparkles, 20)
	end)
	-- arched smoke plumes rising out of the smoke
	local plumeStart = tImpact + 0.8
	for i = 0, 5 do -- six bursts, all before the loop ends at FinaleTime + 0.25
		burst(plumeStart + i * 0.12, plumes, math.max(1, math.ceil(p.PlumeCount / 6)))
	end
	burst(tFinale + 0.1, sparkles, 3)
	burst(tImpact + 0.02, impactRays, 2)
	for i = 0, 3 do
		burst(tImpact + 0.12 + i * 0.4, windRings, 1)
	end

	at(tFinale - 0.05, function() -- third blade flare, just before the cross
		flareAt.WorldCFrame = CFrame.new(target + UP * 6.5 * s)
		flare.Rotation = NumberRange.new(0)
		flare.Size = seq({ { 0, 12 * s }, { 0.3, 16 * s }, { 1, 14 * s } })
		ctx.Emit(flare, 1)
	end)
	-- camera shake (camera-world.md magnitudes): a jolt on the launch, a heavy hit on the
	-- impact, a rumble while the pillar burns, a last kick on the finale
	if p.Shake then
		local k = p.ShakeScale
		at(tLaunch, function()
			ctx.Shake(2.2 * k, 0.4, { Roughness = 15, Position = caster })
		end)
		at(tImpact, function()
			ctx.Shake(11 * k, 1.4, { Roughness = 9, Position = target })
		end)
		at(tImpact + 0.3, function()
			ctx.Shake(1.8 * k, tFinale - tImpact - 0.3, { Roughness = 22, FadeIn = 0.2, Position = target })
		end)
		at(tFinale, function()
			ctx.Shake(5.5 * k, 0.7, { Roughness = 12, Position = target })
		end)
	end
	table.sort(events, function(a, b)
		return a[1] < b[1]
	end)

	------------------------------------------------------------------ per-frame loop
	local pillarWidth = {
		{ tImpact + 0.03, 0 }, { tImpact + 0.06, 15 * s }, { tImpact + 0.4, 11 * s },
		{ tFinale - 0.35, 8.5 * s }, { tFinale - 0.05, 3 * s }, { tFinale, 0 },
	}
	local lightKeys = {
		{ 0, 0 }, { 0.6, 0 }, { 0.62, 0.5 }, { 0.75, 0 }, { tCharge, 0 }, { tCharge + 0.02, 0.6 },
		{ tCharge + 0.2, 0 }, { tImpact, 0 }, { tImpact + 0.02, 1 }, { tImpact + 0.4, 0.55 },
		{ tFinale - 0.05, 0.4 }, { tFinale, 1 }, { tFinale + 0.15, 0 },
	}
	local nextEvent = 1
	local clock = 0
	local endTime = burnEnd + 0.1
	while clock < endTime do
		while nextEvent <= #events and events[nextEvent][1] <= clock do
			events[nextEvent][2]()
			nextEvent += 1
		end

		-- wires
		for i, wire in WIRES do
			updateWire(wire, wireSlots[i], clock)
		end

		-- dash head
		local dashT = (clock - tLaunch) / (tImpact - tLaunch)
		if dashT >= 0 and dashT <= 1 then
			-- rushes most of the way (~0.78 of the path by 45% of the dash), then grinds in
			-- ease out: ~80 studs/s for the first half of the path, ~48 for the rest
			local along = 1 - (1 - dashT) ^ 1.5
			local head = caster:Lerp(target, along) + UP * 2.5 * sc
			headAt.WorldCFrame = CFrame.fromMatrix(head, right, -dashDir)
			streakHead.WorldCFrame = CFrame.new(head)
			streakTail.WorldCFrame = CFrame.new(caster + UP * 2 * sc)
			-- the ground streak is drawn behind the head as it goes
			railFront.WorldCFrame = CFrame.fromMatrix(caster:Lerp(target, along) + UP * 0.08, dashDir, right)
			for _, e in { headBall, headCore, headFlares, pathOrbs } do
				e.Enabled = true
			end
			enableKit(dashKit, true)
		else
			if dashT > 1 then
				railFront.WorldCFrame = CFrame.fromMatrix(target + UP * 0.08, dashDir, right)
			end
			for _, e in { headBall, headCore, headFlares, pathOrbs } do
				e.Enabled = false
			end
			enableKit(dashKit, false)
		end
		-- the line and its haze stay drawn to the target for a moment after the dash lands
		local lineK = track({ { tLaunch - 0.01, 0 }, { tLaunch + 0.01, 1 }, { tImpact, 1 }, { tImpact + 0.15, 0 } }, clock)
		dashLine.Enabled = lineK > 0.01
		dashHaze.Enabled = dashLine.Enabled
		dashLine.Width0, dashLine.Width1 = 0.14 * sc, 0.1 * sc
		dashLine.Transparency = seq({ { 0, 1 - lineK }, { 1, 1 - 0.5 * lineK } })
		dashHaze.Width0, dashHaze.Width1 = 0.9 * sc, 0.5 * sc
		dashHaze.Transparency = seq({ { 0, 1 - 0.65 * lineK }, { 1, 1 - 0.15 * lineK } })
		-- rainbow ground streak: a bright prism (white centre, rainbow rails), then a thin
		-- orange line
		local railW = track({
			{ tLaunch - 0.01, 0 }, { tLaunch + 0.02, 5 * sc }, { tLaunch + 0.3, 4 * sc },
			{ tImpact + 0.05, 0.9 }, { tImpact + 0.6, 0.6 }, { tImpact + 0.7, 0 },
		}, clock)
		rail.Enabled = railW > 0.01
		rail.Width0 = railW
		rail.Width1 = railW
		local orange = track({ { tLaunch + 0.3, 0 }, { tImpact + 0.05, 1 } }, clock)
		rail.Color = ColorSequence.new(WHITE:Lerp(Color3.fromRGB(255, 120, 50), orange))
		local railT = track({ { tLaunch + 0.05, 0 }, { tImpact, 0.15 }, { tImpact + 0.3, 0.55 }, { tImpact + 0.7, 1 } }, clock)
		rail.Transparency = NumberSequence.new(railT)
		railCore.Enabled = rail.Enabled
		railCore.Width0, railCore.Width1 = railW * 0.35, railW * 0.35
		railCore.Transparency = seq({ { 0, 1 }, { 0.15, math.min(1, railT + 0.1) }, { 1, math.min(1, railT + 0.1) } })

		-- pillar (flickers while it burns)
		local width = track(pillarWidth, clock)
		local on = clock >= tImpact + 0.03 and clock < tFinale
		local flicker = 0.85 + 0.15 * math.sin(clock * 47) * math.sin(clock * 23 + 1)
		for _, b in { pillarCore, pillarLines, pillarDark } do
			b.Enabled = on
		end
		pillarCore.Width0 = width * 0.35 * flicker
		pillarCore.Width1 = width * 0.5 * flicker
		pillarLines.Width0 = width * 1.1
		pillarLines.Width1 = width * 1.25
		pillarDark.Width0 = width * 0.6
		pillarDark.Width1 = width * 0.8

		smoke.Enabled = clock >= tImpact + 0.1 and clock < tFinale + 0.1
		motes.Enabled = clock >= tImpact + 0.1 and clock < tFinale - 0.1
		light.Brightness = p.LightBrightness * track(lightKeys, clock)

		-- vignette
		if vignettePart and camera then
			local k = track(vignetteKeys, clock)
			local cf = camera.CFrame * CFrame.new(0, 0, -2)
			vignettePart.CFrame = cf
			local halfH = 2 * math.tan(math.rad(camera.FieldOfView) / 2)
			local view = camera.ViewportSize
			local halfW = halfH * (view.X / math.max(view.Y, 1))
			for _, side in { vigLeft, vigRight } do
				side.Att.Position = Vector3.new(side.Side * halfW * 1.05, 0, 0)
				side.E.Size = NumberSequence.new(halfH * 1.3)
				side.E.Transparency = NumberSequence.new(1 - 0.75 * k)
			end
			vigWash.E.Size = NumberSequence.new(halfW * 1.6)
			vigWash.E.Transparency = NumberSequence.new(1 - track(washKeys, clock))
		end

		clock += ctx.Wait(1 / 240)
	end
	light.Brightness = 0
	if vignettePart then
		for _, side in { vigLeft, vigRight, vigWash } do
			side.E.Transparency = NumberSequence.new(1)
		end
	end
end

return Effect
