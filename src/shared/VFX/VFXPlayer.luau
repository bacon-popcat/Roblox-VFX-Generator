-- ModuleScript: ReplicatedStorage/Shared/VFX/VFXPlayer
-- Plays effects by name. Each effect gets a "ctx" with helpers so that
-- timing respects TimeScale (slow-mo in the harness) and cleanup is automatic.

local TweenService = game:GetService("TweenService")

local VFXPlayer = {}
VFXPlayer.TimeScale = 1

local effectsFolder = script.Parent:WaitForChild("Effects")

local container = Instance.new("Folder")
container.Name = "ActiveVFX"
container.Parent = workspace

local cache = {}

local function getEffect(name)
	if cache[name] then
		return cache[name]
	end
	local moduleScript = effectsFolder:FindFirstChild(name)
	assert(moduleScript, "VFXPlayer: no effect named " .. tostring(name))
	cache[name] = require(moduleScript)
	return cache[name]
end

local function resolveParams(def, overrides)
	local params = table.clone(def.Defaults or {})
	if overrides then
		for key, value in overrides do
			params[key] = value
		end
	end
	return params
end

function VFXPlayer.Play(name, cframe, overrides)
	local def = getEffect(name)
	local timeScale = VFXPlayer.TimeScale

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = container

	local ctx = {
		CFrame = cframe,
		Params = resolveParams(def, overrides),
		Folder = folder,
		TimeScale = timeScale,
	}

	-- Wait in "effect time" (stretches in slow-mo). Returns the effect time that
	-- actually passed, which is usually a bit more than asked (frame granularity).
	function ctx.Wait(seconds)
		return task.wait(seconds / timeScale) * timeScale
	end

	-- Tween in "effect time"
	function ctx.Tween(instance, seconds, props, style, direction)
		local info = TweenInfo.new(
			seconds / timeScale,
			style or Enum.EasingStyle.Quad,
			direction or Enum.EasingDirection.Out
		)
		local tween = TweenService:Create(instance, info, props)
		tween:Play()
		return tween
	end

	-- Burst particles, respecting slow-mo
	function ctx.Emit(emitter, count)
		emitter.TimeScale = timeScale
		emitter:Emit(count)
	end

	-- Invisible anchored part to hang attachments/emitters/lights on
	function ctx.Anchor(at)
		local part = Instance.new("Part")
		part.Name = "Anchor"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.one * 0.1
		part.CFrame = at or cframe
		part.Parent = folder
		return part
	end

	task.spawn(function()
		local ok, err = pcall(def.Play, ctx)
		if not ok then
			warn(("VFXPlayer: effect '%s' errored: %s"):format(name, tostring(err)))
		end
		-- Let particles finish before cleaning up
		ctx.Wait(def.Linger or 1)
		folder:Destroy()
	end)
end

function VFXPlayer.Clear()
	container:ClearAllChildren()
end

return VFXPlayer
