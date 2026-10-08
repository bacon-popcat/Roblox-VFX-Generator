-- ModuleScript: ReplicatedStorage/VFX/Effects/SlashImpact
-- Example effect. Everything tunable lives in Defaults so the harness
-- can expose it as attributes.

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(255, 170, 60),
	Scale = 1,
	SparkCount = 25,
	SparkSpeed = 30,
	FlashTime = 0.25,
	LightBrightness = 6,
}

-- Seconds (effect time) to keep the effect alive after Play returns
Effect.Linger = 0.8

function Effect.Play(ctx)
	local p = ctx.Params
	local anchor = ctx.Anchor()
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	-- Sparks
	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 0
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(p.Color)
	sparks.LightEmission = 1
	sparks.Lifetime = NumberRange.new(0.2, 0.45)
	sparks.Speed = NumberRange.new(p.SparkSpeed * 0.6, p.SparkSpeed)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 6
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3 * p.Scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Parent = attachment
	ctx.Emit(sparks, p.SparkCount)

	-- Flash disc facing the effect's look direction
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Cylinder
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CastShadow = false
	flash.Material = Enum.Material.Neon
	flash.Color = p.Color
	flash.Size = Vector3.new(0.05, 1, 1) * Vector3.new(1, p.Scale, p.Scale)
	flash.CFrame = ctx.CFrame * CFrame.Angles(0, math.rad(90), 0)
	flash.Parent = ctx.Folder
	ctx.Tween(flash, p.FlashTime, {
		Size = Vector3.new(0.05, 8 * p.Scale, 8 * p.Scale),
		Transparency = 1,
	})

	-- Light pop
	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = 12 * p.Scale
	light.Brightness = p.LightBrightness
	light.Parent = anchor
	ctx.Tween(light, p.FlashTime * 1.5, { Brightness = 0 })

	ctx.Wait(p.FlashTime)
end

return Effect
