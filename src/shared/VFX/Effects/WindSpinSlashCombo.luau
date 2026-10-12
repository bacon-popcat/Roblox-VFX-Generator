-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/WindSpinSlashCombo
-- The whole move from the reference: WindBladeTrail wraps the sword during the
-- windup, then WindSpinSlash fires at the end of it while the sword spins round.
-- Use it in the harness to see the full sequence.
--
-- In a game, drive the two effects from the attack animation instead, so they
-- stay in sync with it: play WindBladeTrail at the start of the windup with
-- Duration = time to the hit frame, and WindSpinSlash on the hit frame.
--
-- Weapon: optional runtime override, passed to WindBladeTrail. Without it the
-- trail builds a stand-in katana and this effect spins it through the slash.

local RunService = game:GetService("RunService")

local Effects = script.Parent
local WindBladeTrail = require(Effects:WaitForChild("WindBladeTrail"))
local WindSpinSlash = require(Effects:WaitForChild("WindSpinSlash"))

-- ctx for a child effect: shares the parent's folder, clock and helpers (reads
-- fall through, so a frozen TimeScale reaches the child too) with its own Params
local function childContext(ctx, def, overrides)
	local params = table.clone(def.Defaults)
	for key, value in overrides do
		params[key] = value
	end
	return setmetatable({ Params = params }, { __index = ctx })
end

-- Spins the stand-in katana once around the caster's vertical axis
local function spinDemoSword(ctx, caster, time, turns)
	local parts = {}
	for _, name in { "DemoBlade", "DemoGuard", "DemoHandle" } do
		local part = ctx.Folder:FindFirstChild(name)
		if part then
			table.insert(parts, part)
		end
	end
	if #parts == 0 then
		return
	end
	local start = {}
	for i, part in parts do
		start[i] = caster:ToObjectSpace(part.CFrame)
	end

	local elapsed = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(rawDt)
		if not ctx.Folder.Parent then
			connection:Disconnect()
			return
		end
		elapsed += rawDt * ctx.TimeScale
		local alpha = math.min(elapsed / time, 1)
		alpha = 1 - (1 - alpha) ^ 3 -- fast start, eases out
		local spin = CFrame.Angles(0, -turns * math.pi * 2 * alpha, 0)
		local cframes = {}
		for i, offset in start do
			cframes[i] = caster * spin * offset
		end
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		if alpha >= 1 then
			connection:Disconnect()
		end
	end)
end

local Effect = {}

Effect.Defaults = {
	Scale = 1,
	WindupTime = 0.6, -- seconds of wind on the blade before the slash
}

Effect.Linger = math.max(WindSpinSlash.Linger, WindBladeTrail.Linger)

function Effect.Play(ctx)
	local p = ctx.Params

	local windup = childContext(ctx, WindBladeTrail, {
		Scale = p.Scale,
		Duration = p.WindupTime,
		FadeTime = 0.03, -- the strands vanish as the slash fires, not drag round with the spin
		Weapon = p.Weapon,
	})
	task.spawn(WindBladeTrail.Play, windup)

	ctx.Wait(p.WindupTime)

	if p.Weapon == nil then
		spinDemoSword(ctx, ctx.CFrame, 0.18, 1)
	end
	WindSpinSlash.Play(childContext(ctx, WindSpinSlash, { Scale = p.Scale }))
end

return Effect
