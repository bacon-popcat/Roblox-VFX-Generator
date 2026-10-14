-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/GroundSlam
-- Mesh-based example: expanding shockwave ring + flying rock chunks,
-- plus normal particles for dust and a light pop.
--
-- Uses templates from ReplicatedStorage/Assets/Meshes if they exist:
--   ShockRing  - a flat ring MeshPart, modeled lying flat (Y up), ~2 studs wide
--   Rock       - a rock chunk MeshPart, ~1 stud
-- Without them it falls back to plain parts so you can test right away.

local VFX = script.Parent.Parent
local MeshParticles = require(VFX:WaitForChild("MeshParticles"))
-- MeshFactory publishes templates to ReplicatedStorage.Assets.Meshes (Studio-only)
local meshRoot = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
local meshFolder = meshRoot and meshRoot:FindFirstChild("Meshes")

local fallbacks = {}
local function getTemplate(name)
	local template = meshFolder and meshFolder:FindFirstChild(name)
	if template then
		return template, false
	end
	if not fallbacks[name] then
		local part = Instance.new("Part")
		if name == "ShockRing" then
			part.Shape = Enum.PartType.Cylinder -- disc; axis is X
			part.Size = Vector3.new(0.2, 2, 2)
		else
			part.Size = Vector3.new(0.8, 0.6, 0.7)
		end
		fallbacks[name] = part
	end
	return fallbacks[name], true
end

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(150, 210, 255),
	RockColor = Color3.fromRGB(110, 100, 95),
	Scale = 1,
	RingSize = 14,
	RingTime = 0.35,
	RockCount = 14,
	RockSpeed = 35,
	RockSpread = 55,
	DustCount = 8,
}

Effect.Linger = 1.4

function Effect.Play(ctx)
	local p = ctx.Params

	-- Find the ground under the effect
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { ctx.Folder }
	local origin = ctx.CFrame.Position
	local hit = workspace:Raycast(origin, Vector3.new(0, -20, 0), rayParams)
	local ground = hit and hit.Position or (origin - Vector3.new(0, 2.5, 0))

	-- Shockwave ring: one mesh, tweened
	local ringTemplate, ringIsFallback = getTemplate("ShockRing")
	local ring = ringTemplate:Clone()
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = p.Color
	ring.Transparency = 0.1

	local tilt = ringIsFallback and CFrame.Angles(0, 0, math.rad(90)) or CFrame.identity
	ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0)) * tilt

	local startSize = ring.Size * p.Scale
	local grow = p.RingSize / math.max(startSize.Z, 0.01)
	local endSize = if ringIsFallback
		then Vector3.new(startSize.X, startSize.Y * grow, startSize.Z * grow)
		else Vector3.new(startSize.X * grow, startSize.Y, startSize.Z * grow)
	ring.Size = startSize
	ring.Parent = ctx.Folder
	ctx.Tween(ring, p.RingTime, { Size = endSize, Transparency = 1 }, Enum.EasingStyle.Exponential)

	-- Rock chunks: many meshes, simulated
	local rockTemplate, rockIsFallback = getTemplate("Rock")
	if rockIsFallback then
		rockTemplate.Color = p.RockColor
		rockTemplate.Material = Enum.Material.Slate
	end
	MeshParticles.Burst(ctx, rockTemplate, p.RockCount, {
		Origin = ground + Vector3.new(0, 0.5, 0),
		Direction = Vector3.yAxis,
		Spread = p.RockSpread,
		Speed = NumberRange.new(p.RockSpeed * 0.6, p.RockSpeed),
		Lifetime = NumberRange.new(0.7, 1.1),
		Acceleration = Vector3.new(0, -110, 0),
		SpinSpeed = NumberRange.new(180, 540),
		Scale = p.Scale,
		SpawnRadius = 1.5 * p.Scale,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.75, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
	})

	-- Dust: normal particles are still the right tool for soft stuff
	local anchor = ctx.Anchor(CFrame.new(ground + Vector3.new(0, 0.5, 0)))
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(170, 160, 150))
	dust.LightEmission = 0
	dust.LightInfluence = 1
	dust.Lifetime = NumberRange.new(0.6, 1)
	dust.Speed = NumberRange.new(8, 14)
	dust.Drag = 4
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2 * p.Scale),
		NumberSequenceKeypoint.new(1, 4 * p.Scale),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Parent = attachment
	ctx.Emit(dust, p.DustCount)

	-- Light pop
	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = 16 * p.Scale
	light.Brightness = 5
	light.Parent = anchor
	ctx.Tween(light, p.RingTime * 1.5, { Brightness = 0 })

	ctx.Wait(p.RingTime)
end

return Effect
