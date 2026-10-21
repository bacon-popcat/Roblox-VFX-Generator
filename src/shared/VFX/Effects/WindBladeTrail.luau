-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/WindBladeTrail
-- Wind wrapping a sword during the windup of WindSpinSlash. Layers: wavy
-- grass-like strands (Beams) rooted on the blade that fan out past the tip and
-- whip behind it as it moves, dark strands woven in (their black twins), a thin glow
-- along the edge, a weapon-trail pair (a thin hot core and a wide soft wisp, both
-- textured), and lime specks shed from the tip.
--
-- Trail lifetimes are real time, so they are divided by ctx.TimeScale: the trails keep
-- their length in slow motion. In a VFXScrub freeze a trail still loses its segments;
-- judge it while the effect plays slowly.
--
-- Weapon: pass the blade part as a runtime override (not a Default, since
-- instances can't be attributes):
--   VFXPlayer.Play("WindBladeTrail", root.CFrame, { Weapon = bladePart, Duration = 0.6 })
-- The blade runs along the part's longest axis, tip toward +axis. For exact
-- control add Attachments named "BladeBase" and "BladeTip" to the part.
-- Without a Weapon (e.g. in the harness) the effect builds a stand-in katana at
-- ctx.CFrame and plays the windup pose from the reference: blade raised, then
-- swung back over the shoulder.
--
-- Beam textures run along the beam with the image's top at Attachment0, so each
-- strand is Beam(tip -> root): the grass blades converge on the sword and fan out
-- at the tip.

local RunService = game:GetService("RunService")

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	Strands = "rbxassetid://91858314987113", -- StaticVFXTextures/grass1Other (three curved blades)
	Needle = "rbxassetid://10614304526", -- StaticVFXTextures/Sideways Spec 41 (thin needle)
	TrailStreaks = "rbxassetid://13280046773", -- MigratedBeams/BeamSoftBlurredStreaks (soft streaks: the wisp)
	TrailCore = "rbxassetid://10614304526", -- StaticVFXTextures/Sideways Spec 41 (thin needle: the hot core)
	Sparkle = "rbxassetid://16444981264", -- StaticVFXTextures/Star153
}

local rng = Random.new()

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

local function quiet(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- Base and tip of the blade in world space
local function bladeEnds(weapon)
	local base = weapon:FindFirstChild("BladeBase")
	local tip = weapon:FindFirstChild("BladeTip")
	if base and tip and base:IsA("Attachment") and tip:IsA("Attachment") then
		return base.WorldPosition, tip.WorldPosition
	end
	local size = weapon.Size
	local cf = weapon.CFrame
	local axis, half
	if size.X >= size.Y and size.X >= size.Z then
		axis, half = cf.RightVector, size.X / 2
	elseif size.Y >= size.Z then
		axis, half = cf.UpVector, size.Y / 2
	else
		axis, half = -cf.LookVector, size.Z / 2
	end
	return cf.Position - axis * half, cf.Position + axis * half
end

--------------------------------------------------------------------------------
-- Stand-in katana and the reference windup pose (used when no Weapon is given)

local DEMO_BLADE_LENGTH = 4.4

-- Builds a simple katana in ctx.Folder. Returns the blade part (Y = blade axis)
-- and a function that places the whole sword from a grip CFrame.
local function buildDemoKatana(ctx, scale)
	local blade = quiet(Instance.new("Part"))
	blade.Name = "DemoBlade"
	blade.Size = Vector3.new(0.08, DEMO_BLADE_LENGTH, 0.18) * scale
	blade.Material = Enum.Material.SmoothPlastic
	blade.Color = Color3.fromRGB(90, 65, 40)
	blade.Parent = ctx.Folder

	local guard = quiet(Instance.new("Part"))
	guard.Name = "DemoGuard"
	guard.Shape = Enum.PartType.Cylinder
	guard.Size = Vector3.new(0.12, 0.6, 0.6) * scale
	guard.Material = Enum.Material.Metal
	guard.Color = Color3.fromRGB(70, 60, 45)
	guard.Parent = ctx.Folder

	local handle = quiet(Instance.new("Part"))
	handle.Name = "DemoHandle"
	handle.Size = Vector3.new(0.22, 1.2, 0.26) * scale
	handle.Material = Enum.Material.Fabric
	handle.Color = Color3.fromRGB(25, 25, 30)
	handle.Parent = ctx.Folder

	local parts = { blade, guard, handle }
	local offsets = {
		CFrame.new(0, (0.65 + DEMO_BLADE_LENGTH / 2) * scale, 0),
		CFrame.new(0, 0.6 * scale, 0) * CFrame.Angles(0, 0, math.rad(90)),
		CFrame.new(0, 0, 0),
	}
	local function place(grip)
		local cframes = {}
		for i, offset in offsets do
			cframes[i] = grip * offset
		end
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
	return blade, place
end

-- Grip CFrame (blade along +Y) relative to the caster at time t of a windup that
-- lasts `duration`: raised overhead, then drawn back over the left shoulder so the
-- blade points up and behind (caster space: -X left, +Z behind).
local function bladeAlong(position, direction)
	local up = direction.Unit
	local right = up:Cross(Vector3.zAxis)
	if right.Magnitude < 0.1 then
		right = up:Cross(Vector3.xAxis)
	end
	return CFrame.fromMatrix(position, right.Unit, up)
end
local RAISED = bladeAlong(Vector3.new(0.6, 1.5, -0.7), Vector3.new(0.12, 1, -0.05))
local DRAWN_BACK = bladeAlong(Vector3.new(-0.7, 1.3, 0.2), Vector3.new(-0.8, 0.3, 0.45))

local function demoGrip(caster, t, duration, scale)
	local swingStart, swingEnd = duration * 0.3, duration * 0.75
	local alpha = math.clamp((t - swingStart) / (swingEnd - swingStart), 0, 1)
	alpha = alpha * alpha * (3 - 2 * alpha) -- smoothstep
	local pose = RAISED:Lerp(DRAWN_BACK, alpha)
	return caster * CFrame.new(pose.Position * scale) * pose.Rotation
end

--------------------------------------------------------------------------------

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(70, 235, 30), -- lime strands
	CoreColor = Color3.fromRGB(160, 240, 90), -- strand tips
	BaseColor = Color3.fromRGB(150, 135, 45), -- olive where strands meet the blade
	DarkColor = Color3.fromRGB(8, 30, 12), -- dark strands
	Scale = 1,
	Duration = 0.6, -- seconds the wind stays on the blade (the windup length)
	StrandCount = 4,
	DarkStrandCount = 3,
	StrandReach = 2.2, -- studs the strands reach past the tip
	StrandWidth = 1.3, -- studs at the fanned-out end
	StrandLag = 0.04, -- seconds the strand tips trail the blade
	WaveAmount = 0.6, -- studs of side-to-side whip
	FadeTime = 0.12, -- seconds the strands take to vanish after Duration
	TrailLifetime = 0.1, -- the thin hot core trail (0.04-0.15 studied)
	WispLifetime = 0.3, -- the wide soft wisp trail (0.15-0.4 studied)
	WispReach = 1.2, -- studs the wisp reaches past the tip
	SpeckInterval = 0.04, -- seconds between specks shed from the tip
}

Effect.Linger = 0.8 -- specks (0.45 s) and the wisp trail fading out

-- Returns the blade part (the given Weapon or the stand-in katana).
function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local duration = p.Duration
	local fadeTime = math.max(p.FadeTime, 1e-3)

	local weapon = p.Weapon
	local placeDemo
	if typeof(weapon) ~= "Instance" or not weapon:IsA("BasePart") then
		weapon, placeDemo = buildDemoKatana(ctx, s)
		placeDemo(demoGrip(ctx.CFrame, 0, duration, s))
	end

	local anchor = ctx.Anchor(CFrame.identity)
	local function attachment()
		local a = Instance.new("Attachment")
		a.Parent = anchor
		return a
	end

	-- Blade ends: the trails and the specks use these; the wisp spans a little wider
	local baseAttachment = attachment()
	local tipAttachment = attachment()
	local wispBase = attachment()
	local wispTip = attachment()

	-- Strand roots: two points along the blade, shared by the strands
	local roots = { attachment(), attachment() }
	local ROOT_ALONG = { 0.05, 0.35 } -- fraction of the blade from its base

	-- Strands: lime (additive) and dark (normal blend), each its own tip attachment
	local strands = {}
	local total = p.StrandCount + p.DarkStrandCount
	for i = 1, total do
		local dark = i > p.StrandCount
		local tip = attachment()
		local beam = Instance.new("Beam")
		beam.Texture = ASSETS.Strands
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureLength = 1
		beam.FaceCamera = true
		beam.Segments = 14
		beam.Attachment0 = tip -- image top (fanned-out ends) at the tip
		beam.Attachment1 = roots[(i % 2) + 1]
		beam.LightInfluence = 0
		if dark then
			beam.LightEmission = 0
			beam.Color = ColorSequence.new(p.DarkColor)
			beam.ZOffset = 1
		else
			-- Partly additive: fully additive lime washes out to mint over light ground
			beam.LightEmission = 0.15
			beam.Brightness = 1.1
			beam.Color = colors({ { 0, p.CoreColor }, { 0.3, p.Color }, { 0.75, p.Color }, { 1, p.BaseColor } })
		end
		beam.Parent = anchor
		table.insert(strands, {
			Beam = beam,
			Tip = tip,
			Dark = dark,
			Reach = p.StrandReach * s * rng:NextNumber(dark and 0.5 or 0.7, dark and 0.9 or 1.25),
			Width = p.StrandWidth * s * rng:NextNumber(dark and 0.7 or 0.75, dark and 0.9 or 1.1),
			Side = rng:NextNumber(-1, 1), -- lateral spread of the tip
			Phase = rng:NextNumber(0, math.pi * 2),
			Frequency = rng:NextNumber(9, 15),
			Position = nil, -- lagged tip position
		})
	end

	-- Soft green glow hugging the blade
	local glow = Instance.new("Beam")
	glow.Texture = ASSETS.Needle
	glow.TextureMode = Enum.TextureMode.Stretch
	glow.FaceCamera = true
	glow.Attachment0 = tipAttachment
	glow.Attachment1 = baseAttachment
	glow.LightEmission = 1
	glow.LightInfluence = 0
	glow.Brightness = 2
	glow.Color = colors({ { 0, p.CoreColor }, { 1, p.Color } })
	glow.Transparency = seq({ { 0, 0.2 }, { 1, 0.6 } })
	glow.Parent = anchor

	-- Weapon trails in a pair: a thin hot core and a wide soft wisp, both textured and
	-- tapering to nothing (lifetimes divided by TimeScale: Trail lifetimes are real time)
	local timeScale = math.max(ctx.TimeScale, 1e-3)
	local trail = Instance.new("Trail")
	trail.Attachment0 = baseAttachment
	trail.Attachment1 = tipAttachment
	trail.Texture = ASSETS.TrailCore
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.Lifetime = p.TrailLifetime / timeScale
	trail.MinLength = 0.05
	trail.FaceCamera = false
	trail.LightEmission = 0
	trail.LightInfluence = 0
	trail.Brightness = 12
	trail.Color = colors({ { 0, p.CoreColor }, { 1, p.Color } })
	trail.Transparency = seq({ { 0, 0 }, { 1, 1 } })
	trail.WidthScale = seq({ { 0, 0.5 }, { 1, 0 } })
	trail.Parent = anchor
	local wisp = Instance.new("Trail")
	wisp.Attachment0 = wispBase
	wisp.Attachment1 = wispTip
	wisp.Texture = ASSETS.TrailStreaks
	wisp.TextureMode = Enum.TextureMode.Stretch
	wisp.Lifetime = p.WispLifetime / timeScale
	wisp.MinLength = 0.05
	wisp.FaceCamera = false
	wisp.LightEmission = 0.65
	wisp.LightInfluence = 0
	wisp.Brightness = 1.5
	wisp.Color = colors({ { 0, p.Color }, { 1, p.BaseColor } })
	wisp.Transparency = seq({ { 0, 0.35 }, { 1, 1 } })
	wisp.WidthScale = seq({ { 0, 1 }, { 1, 0 } })
	wisp.Parent = anchor

	-- Lime specks shed from the tip
	local specks = Instance.new("ParticleEmitter")
	specks.Rate = 0
	specks.Texture = ASSETS.Sparkle
	specks.LightEmission = 1
	specks.LightInfluence = 0
	specks.Brightness = 2
	specks.Color = colors({ { 0, p.Color:Lerp(p.CoreColor, 0.4) }, { 1, p.Color } })
	specks.Lifetime = NumberRange.new(0.25, 0.45)
	specks.Speed = NumberRange.new(1, 3)
	specks.SpreadAngle = Vector2.new(180, 180)
	specks.Drag = 3
	specks.Size = seq({ { 0, 0 }, { 0.15, 0.18 * s }, { 1, 0 } })
	specks.Parent = tipAttachment

	local elapsed = 0
	local speckClock = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(rawDt)
		if not ctx.Folder.Parent then
			connection:Disconnect()
			return
		end
		local dt = rawDt * ctx.TimeScale
		elapsed += dt
		if elapsed > duration + fadeTime then
			connection:Disconnect()
			trail.Enabled = false
			wisp.Enabled = false
			glow.Enabled = false
			for _, strand in strands do
				strand.Beam.Enabled = false
			end
			return
		end

		if placeDemo and elapsed <= duration then
			placeDemo(demoGrip(ctx.CFrame, elapsed, duration, s))
		end

		local basePos, tipPos = bladeEnds(weapon)
		local axis = (tipPos - basePos)
		local length = axis.Magnitude
		axis = axis.Unit
		-- Two directions across the blade, for spread and bending
		local across = axis:Cross(Vector3.yAxis)
		if across.Magnitude < 0.1 then
			across = axis:Cross(Vector3.xAxis)
		end
		across = across.Unit
		local across2 = axis:Cross(across).Unit

		baseAttachment.WorldPosition = basePos
		tipAttachment.WorldPosition = tipPos
		wispBase.WorldPosition = basePos + axis * length * 0.2
		wispTip.WorldPosition = tipPos + axis * p.WispReach * s
		for i, root in roots do
			root.WorldCFrame = CFrame.fromMatrix(basePos + axis * length * ROOT_ALONG[i], across, axis)
		end

		-- Fade in over 0.08s, out over the last fadeTime
		local envelope = math.min(elapsed / 0.08, 1)
		if elapsed > duration then
			envelope *= 1 - (elapsed - duration) / fadeTime
		end

		glow.Width0 = 0.6 * s * envelope
		glow.Width1 = 0.35 * s * envelope

		local follow = 1 - math.exp(-dt / math.max(p.StrandLag, 1e-3))
		for _, strand in strands do
			local target = tipPos
				+ axis * strand.Reach
				+ (across * strand.Side + across2 * strand.Side * 0.5) * strand.Reach * 0.35
			strand.Position = if strand.Position then strand.Position:Lerp(target, follow) else target
			-- Tip attachment: X axis across the blade so CurveSize bends the strand sideways
			strand.Tip.WorldCFrame = CFrame.fromMatrix(strand.Position, across, axis)

			local wave = math.sin(elapsed * strand.Frequency + strand.Phase)
			local whip = math.sin(elapsed * strand.Frequency * 1.7 + strand.Phase * 2)
			strand.Beam.CurveSize0 = wave * p.WaveAmount * s
			strand.Beam.CurveSize1 = whip * p.WaveAmount * 0.5 * s
			strand.Beam.Width0 = strand.Width * envelope
			strand.Beam.Width1 = strand.Width * 0.25 * envelope
		end

		speckClock += dt
		if speckClock >= p.SpeckInterval and envelope > 0.5 then
			speckClock = 0
			ctx.Emit(specks, 1)
		end
	end)

	ctx.Wait(duration + fadeTime)
	return weapon
end

return Effect
