-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/ChromaticStrike
-- A white, prismatic ranged strike: ink-and-light wires whip from the caster to the target,
-- the caster charges (chromatic ground ring, a black void frame, a huge prismatic
-- starburst) and fires a tunnelling dash along a rainbow ground streak, and the target
-- erupts: a giant jagged white flash with rainbow fringes, a light pillar, halo rings that
-- rise around it, crystal spikes with rainbow tips, glitch ribbons, horizontal cross-flares,
-- leaves and debris, a 4-point cross finale and a crown of arched smoke plumes.
-- Layers: wires (core beams, ink smudge, sparkle heads), caster sparks/void/starburst/
-- rays/crystals/bokeh/dark shell/chromatic shards, dash head (three rolling drill ribbons
-- + black smoke),
-- tunnel rings, rainbow ground streak, impact flash (white + red/cyan copies for the
-- fringe), pillar beams, dark ground shockwave, halo rings, crystal spikes, chromatic
-- blobs, glitch ribbons, flares, cross finale, smoke disc, arched plumes, leaves, rocks,
-- sparkles, light, screen-edge vignette (magenta left, teal right).
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
	LineFlare = "rbxassetid://103854278038347", -- StaticVFXTextures/Blurry Horizontal Flare (thin white line)
	ChromRing = "rbxassetid://109324703201714", -- StaticVFXTextures/Chromatic Smoke Circle
	GlitchLine = "rbxassetid://84324997861606", -- FlipbookTextures/Chromatic Glitching Line Slash (Grid4x4)
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
	PillarCore = "rbxassetid://7135001284", -- MigratedBeams/BeamStretchedGlowColumn
	PillarLines = "rbxassetid://6091329339", -- MigratedBeams/BeamGlowingStreakLines
	PillarDark = "rbxassetid://15398097961", -- MigratedBeams/BeamFlickeringSmokeColumn (tinted black)
}

local WHITE = Color3.new(1, 1, 1)
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

-- Wire paths: { along (0 caster .. 1 target), height, side (+ = caster's right) }; heights and
-- sides are studs at the default Scale. Measured on the far take (20 fps): salvo 1 is a low
-- glassy ribbon and a high arch over the left; salvo 2 is two strands that shoot very high in
-- a V, loop over each other and come down into the target. Each wire stays drawn from the
-- caster to its tip until FadeAt, then fades while its tail pulls in.
local WIRES = {
	{ -- 1A: low glassy ribbon at chest height
		Launch = 0.1,
		Travel = 0.5,
		Soft = true, -- a smoky white streak, not a kinked wire
		FadeAt = 1.0,
		Fade = 0.15,
		Width = 3.5,
		Points = { { 0, 3, 0 }, { 0.15, 3.5, 0.8 }, { 0.35, 2.8, -0.6 }, { 0.6, 3.4, 0.6 }, { 0.82, 3, -0.3 }, { 1, 3, 0 } },
	},
	{ -- 1B: steep rise, a high arch over the left, dives into the target
		Launch = 0.12,
		Travel = 0.45,
		FadeAt = 0.8,
		Fade = 0.2,
		Width = 1,
		Points = {
			{ 0, 3, 0 }, { 0.02, 8.7, -1 }, { 0.08, 11.4, -2.5 }, { 0.25, 12.8, -3 }, { 0.5, 12.1, -1.5 },
			{ 0.75, 10.2, 0 }, { 0.92, 7, 0.3 }, { 1, 4, 0 },
		},
	},
	{ -- 2A: shoots very high up the left, loops back over itself, then down into the target
		Launch = 0.6,
		Travel = 0.45,
		FadeAt = 1.0,
		Fade = 0.12,
		Width = 1,
		Points = {
			{ 0, 3, 0 }, { 0.02, 10.2, -1 }, { 0.05, 14.8, -2 }, { 0.1, 17.9, -3 }, { 0.2, 17.1, -6 }, { 0.22, 14, -3 },
			{ 0.15, 12.5, 1 }, { 0.25, 14.8, 4 }, { 0.45, 15.6, 2 }, { 0.7, 13.2, 0 }, { 0.9, 10.2, 0 }, { 1, 4, 0 },
		},
	},
	{ -- 2B: up the right in a V with 2A, curls, then down into the target
		Launch = 0.62,
		Travel = 0.42,
		FadeAt = 1.0,
		Fade = 0.12,
		Width = 1,
		Points = {
			{ 0, 3, 0 }, { 0.06, 9.4, 2 }, { 0.15, 13.2, 4 }, { 0.3, 15.6, 4 }, { 0.45, 14, 2 }, { 0.5, 11.7, 3 },
			{ 0.65, 13.2, 4 }, { 0.85, 10.9, 1 }, { 1, 4, 0 },
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
	FinaleTime = 3.0, -- the pillar collapses into the 4-point cross
	WireWidth = 0.3, -- core width (x caster scale); the ink smudge is 7x wider
	WireSegments = 3, -- beam segments per wire (fewer = cheaper, angular loops)
	SmudgeRate = 70, -- smoke smudge puffs / s per wire tip while it travels
	SparkCount = 16, -- caster spark bursts (the later bursts are fractions of it)
	SpeckCount = 16, -- black shrapnel at the impact (the pre-hits use fractions of it)
	BokehCount = 10, -- white dots flying out inside the caster's shell
	SpikeRate = 45, -- sets the crystal spikes per 0.07 s step (SpikeRate * 0.07, split over two fans)
	SmokeRate = 60, -- ground smoke puffs / s while the pillar burns
	LeafCount = 14,
	RockCount = 12,
	PlumeCount = 12, -- arched smoke hooks in total
	Vignette = true,
	LightBrightness = 1.5,
	LightRange = 6,
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
	local ringHighAt = attachment(base, CFrame.new(target + UP * 8 * s))
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
	local spikePart = ctx.Anchor(CFrame.new(target + UP * 3 * s))
	spikePart.Size = Vector3.new(18, 0.2, 18) * s
	local smokePart = ctx.Anchor(CFrame.new(target + UP * 2 * s))
	smokePart.Size = Vector3.new(30, 0.2, 30) * s
	local plumePart = ctx.Anchor(CFrame.new(target + UP * 5 * s))
	plumePart.Size = Vector3.new(26, 0.2, 26) * s

	------------------------------------------------------------------ wires
	-- Each wire is WireSegments cubic beam segments from its tail to its tip along a
	-- spline, drawn twice: a thin bright core with a tiled kinked texture, and a wider ink
	-- smudge behind it.
	local segments = math.max(1, math.floor(p.WireSegments))
	local wireSlots = {}
	for slot, wireDef in WIRES do
		local atts = {}
		for i = 1, segments + 1 do
			atts[i] = attachment(base, CFrame.new(caster))
		end
		local b = atts[#atts]
		local core = {
			Texture = wireDef.Soft and ASSETS.Smoke or ASSETS.WireBeam,
			TextureMode = Enum.TextureMode.Wrap,
			TextureLength = 3 * sc,
			Width0 = p.WireWidth * wireDef.Width * sc,
			Width1 = p.WireWidth * wireDef.Width * sc,
			Color = ColorSequence.new(p.Color),
			Brightness = 3,
			ZOffset = 0.5,
			Enabled = false,
		}
		local inkProps = {
			Texture = ASSETS.Smoke,
			TextureMode = Enum.TextureMode.Wrap,
			TextureLength = 3 * sc,
			TextureSpeed = 0.6,
			Width0 = p.WireWidth * (2.5 + 1.5 * wireDef.Width) * sc,
			Width1 = p.WireWidth * (2.5 + 1.5 * wireDef.Width) * sc,
			Color = ColorSequence.new(ink),
			LightEmission = 0,
			Enabled = false,
		}
		local tip = emitter(b, { -- bright head + glitter shed along the wire
			Texture = wireDef.Soft and ASSETS.ChromWisp or ASSETS.Sparkle,
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
		local smudge = emitter(b, { -- smoke puffs billowing off the tip (grey, a few dark)
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
		local cores, inks = {}, {}
		for i = 1, segments do
			cores[i] = beam(atts[i], atts[i + 1], core)
			inks[i] = beam(atts[i], atts[i + 1], inkProps)
		end
		wireSlots[slot] = { Atts = atts, Cores = cores, Inks = inks, Tip = tip, Smudge = smudge }
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
		if not on then
			slot.Tip.Enabled = false
			slot.Smudge.Enabled = false
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
		local coreT = seq({ { 0, math.clamp(0.45 + 0.55 * fadeK, 0, 1) }, { 1, fadeK } })
		local inkT = NumberSequence.new(math.clamp(0.3 + 0.7 * fadeK, 0, 1))
		for i = 1, segments do
			for _, b in { slot.Cores[i], slot.Inks[i] } do
				b.CurveSize0 = speeds[i] * step / 3
				b.CurveSize1 = -speeds[i + 1] * step / 3
			end
			slot.Cores[i].Transparency = coreT
			slot.Inks[i].Transparency = inkT
		end
		showWire(slot, true)
		local traveling = tipS < 0.999
		slot.Tip.Enabled = traveling
		slot.Smudge.Enabled = traveling
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
		Size = sizeRange(1 * sc, 2 * sc),
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
		Size = seq({ { 0, 0.8 * sc, 0.25 * sc }, { 0.3, 1.4 * sc, 0.45 * sc }, { 1, 1 * sc, 0.3 * sc } }),
		Transparency = seq({ { 0, 0.2 }, { 0.7, 0.3 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		Brightness = 2,
		ZOffset = 1,
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
	local headAt = attachment(base, CFrame.fromMatrix(caster + UP * 2.5 * sc, right, dashDir))
	-- drilling head (motion.md "a drilling dash"): three flat ribbons fanned round the dash
	-- axis that roll 180 degrees while they narrow; each has its own scroll so they never line up
	local drill = {}
	for i = 1, 3 do
		local tail = attachment(base, CFrame.new(caster))
		local tip = attachment(base, CFrame.new(caster))
		drill[i] = {
			Tail = tail,
			Tip = tip,
			Beam = beam(tail, tip, {
				Texture = ASSETS.PillarLines,
				TextureMode = Enum.TextureMode.Wrap,
				TextureLength = (2 + i) * sc,
				TextureSpeed = 3 + 3 * i,
				FaceCamera = false,
				Segments = 2,
				Color = ColorSequence.new(p.Color),
				Brightness = 3,
				ZOffset = 1.5,
				Transparency = seq({ { 0, 1 }, { 0.35, 0.35 }, { 1, 0 } }), -- clear at the tail
				Enabled = false,
			}),
		}
	end
	local headSmoke = emitter(headAt, { -- black smoke cylinder it bores through
		Texture = ASSETS.Smoke,
		Color = ColorSequence.new(ink),
		LightEmission = 0,
		Rate = 90,
		Enabled = false,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.15, 0.3),
		Size = seq({ { 0, 1.6 * sc }, { 1, 2.6 * sc } }),
		Transparency = seq({ { 0, 0.25 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360),
		TimeScale = ctx.TimeScale,
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
	local flashRed = flashEmitter(p.FringeRed, 16.5 * s, 1.3)
	local flashBlue = flashEmitter(p.FringeBlue, 16 * s, 1.3)
	local flashWhite = flashEmitter(p.Color, 15.3 * s, 2)
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
		Brightness = 3,
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
			Transparency = seq({ { 0, 0.2 }, { 0.7, 0.35 }, { 1, 1 } }),
			Rotation = lean,
			Brightness = 1.2,
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
	local glitch = emitter(spikePart, { -- black-edged rainbow glitch ribbons
		Texture = ASSETS.GlitchLine,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Shape = Enum.ParticleEmitterShape.Disc,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.12, 0.18),
		Size = sizeRange(4 * s, 6 * s),
		Transparency = NumberSequence.new(0),
		Rotation = NumberRange.new(-60, 60),
		Brightness = 2,
		ZOffset = 3,
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
		Size = seq({ { 0, 9 * s }, { 0.33, 2.2 * s }, { 0.66, 0.4 * s }, { 1, 0 } }),
		Transparency = seq({ { 0, 0 }, { 0.66, 0 }, { 1, 1 } }),
		Brightness = 4,
		ZOffset = 5,
	})
	local bar = emitter(crossAt, { -- thick soft white bars of the finale cross (emitted twice)
		Texture = ASSETS.Glow,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.1),
		Size = seq({ { 0, 12 * s }, { 0.5, 8 * s }, { 1, 1.5 * s } }),
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
		Size = seq({ { 0, 2 * s }, { 1, 2.5 * s } }),
		Squash = NumberSequence.new(0.6), -- the hook texture is 1:2 tall; a little squat
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
	light.Range = p.LightRange * s
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
	burst(0, sparks, p.SparkCount)
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
	burst(0.45, sparks, math.ceil(p.SparkCount * 0.6))
	for i = 0, 3 do -- glitter spraying off the caster while the low streak runs
		burst(0.2 + i * 0.08, bokeh, math.ceil(p.BokehCount * 0.2))
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
		burst(tLaunch + 0.2 + i * 0.07, glitchInk, 2)
	end
	for i = 0, 4 do
		burst(tLaunch + 0.25 + i * 0.05, shards, 4)
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
		ctx.Emit(puffs, 8)
		ctx.Emit(targetSpecks, p.SpeckCount) -- black shrapnel
		ctx.Emit(sparkles, 14)
	end)
	at(tImpact + 0.15, function()
		ctx.Emit(ringBase, 1)
		ctx.Emit(ringBaseOuter, 1)
		ctx.Emit(chromSpikes, 6)
	end)
	-- crystal spikes, rainbow tips and prismatic patches: bursts every ~0.07 s
	local burn = tImpact + 0.12
	while burn < tFinale - 0.15 do
		local n = math.max(1, math.floor(p.SpikeRate * 0.07 + 0.5))
		burst(burn, spikesLeft, math.ceil(n / 2))
		burst(burn + 0.01, spikesRight, math.ceil(n / 2))
		burst(burn + 0.03, chromSpikes, math.max(1, math.floor(n / 2)))
		if burn < tFinale - 0.4 then
			burst(burn + 0.02, blobs, 2)
		end
		burn += 0.07
	end
	for i = 0, 5 do -- dark ink core at the target's feet while it burns
		burst(tImpact + 0.12 + i * 0.12, inkCore, 2)
	end
	-- glitch ribbons
	for _, time in { tImpact + 0.2, tImpact + 0.28, tImpact + 0.75, tImpact + 0.85, tImpact + 1.1 } do
		burst(time, glitch, 1)
	end
	-- upper halo waves
	burst(tImpact + 0.2, ringUp, 1)
	burst(tImpact + 0.25, ringUpOuter, 1)
	burst(tImpact + 0.9, ringUp, 1)
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
	end)
	-- arched smoke plumes rising out of the smoke
	local plumeStart = tImpact + 0.8
	for i = 0, 5 do -- six bursts, all before the loop ends at FinaleTime + 0.25
		burst(plumeStart + i * 0.12, plumes, math.max(1, math.ceil(p.PlumeCount / 6)))
	end
	burst(tFinale + 0.1, sparkles, 3)
	burst(tImpact + 0.02, impactRays, 2)
	for i = 0, 3 do
		burst(tImpact + 0.12 + i * 0.25, windRings, 1)
	end

	at(tFinale - 0.05, function() -- third blade flare, just before the cross
		flareAt.WorldCFrame = CFrame.new(target + UP * 6.5 * s)
		flare.Rotation = NumberRange.new(0)
		flare.Size = seq({ { 0, 12 * s }, { 0.3, 16 * s }, { 1, 14 * s } })
		ctx.Emit(flare, 1)
	end)
	table.sort(events, function(a, b)
		return a[1] < b[1]
	end)

	------------------------------------------------------------------ per-frame loop
	local pillarWidth = {
		{ tImpact + 0.03, 0 }, { tImpact + 0.06, 11 * s }, { tImpact + 0.4, 9 * s },
		{ tFinale - 0.35, 7 * s }, { tFinale - 0.05, 3 * s }, { tFinale, 0 },
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
			local along = dashT ^ 0.9 -- near-constant ~70 studs/s, halfway at ~1.6 s
			local head = caster:Lerp(target, along) + UP * 2.5 * sc
			headAt.WorldCFrame = CFrame.fromMatrix(head, right, dashDir)
			local roll = math.pi * dashT
			local width = 6 * sc * (1 - 0.8 * dashT)
			for i, ribbon in drill do
				-- X along the dash, Y (the beam's width) pointing out from the axis
				local angle = roll + (i - 1) * 2 * math.pi / 3
				local out = right * math.cos(angle) + UP * math.sin(angle)
				ribbon.Tail.WorldCFrame = CFrame.fromMatrix(head - dashDir * 7 * sc, dashDir, out)
				ribbon.Tip.WorldCFrame = CFrame.fromMatrix(head, dashDir, out)
				ribbon.Beam.Width0 = width
				ribbon.Beam.Width1 = width * 0.15
				ribbon.Beam.Enabled = true
			end
			headSmoke.Enabled = true
		else
			for _, ribbon in drill do
				ribbon.Beam.Enabled = false
			end
			headSmoke.Enabled = false
		end
		-- rainbow ground streak: wide twin rails, then a thin orange line
		local railW = track({
			{ tLaunch - 0.01, 0 }, { tLaunch + 0.02, 9 * sc }, { tLaunch + 0.3, 7 * sc },
			{ tImpact + 0.05, 0.9 }, { tImpact + 0.6, 0.6 }, { tImpact + 0.7, 0 },
		}, clock)
		rail.Enabled = railW > 0.01
		rail.Width0 = railW
		rail.Width1 = railW
		local orange = track({ { tLaunch + 0.3, 0 }, { tImpact + 0.05, 1 } }, clock)
		rail.Color = ColorSequence.new(WHITE:Lerp(Color3.fromRGB(255, 120, 50), orange))
		rail.Transparency = NumberSequence.new(track({ { tLaunch + 0.05, 0 }, { tLaunch + 0.3, 0.45 }, { tImpact + 0.3, 0.55 }, { tImpact + 0.7, 1 } }, clock))

		-- pillar (flickers while it burns)
		local width = track(pillarWidth, clock)
		local on = clock >= tImpact + 0.03 and clock < tFinale
		local flicker = 0.85 + 0.15 * math.sin(clock * 47) * math.sin(clock * 23 + 1)
		for _, b in { pillarCore, pillarLines, pillarDark } do
			b.Enabled = on
		end
		pillarCore.Width0 = width * 0.35 * flicker
		pillarCore.Width1 = width * 0.5 * flicker
		pillarLines.Width0 = width * 1.6
		pillarLines.Width1 = width * 1.8
		pillarDark.Width0 = width * 0.6
		pillarDark.Width1 = width * 0.8

		smoke.Enabled = clock >= tImpact + 0.1 and clock < tFinale + 0.1
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
