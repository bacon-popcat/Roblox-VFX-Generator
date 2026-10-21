-- Runs every effect in Shared.VFX.Effects on the virtual clock and reports, per effect:
-- errors (with a traceback), when Play returned, whether Linger covers every particle and
-- mesh particle, the peak particle count and emission rate, instances, lights, and anything
-- left outside ctx.Folder. Appended to the bundle by run.mjs; `Runtime` is in scope.
-- EFFECTS (set by run.mjs) lists { name, overrides } cases to run.

local RECORD = Runtime.RECORD
local RS = game:GetService("ReplicatedStorage")
local VFX = RS.Shared.VFX

local container = Instance.new("Folder")
container.Name = "ActiveVFX"
container.Parent = workspace

local function count(map, key, n)
	map[key] = (map[key] or 0) + (n or 1)
end

local function runCase(case, timeScale)
	local name, overrides = case[1], case[2] or {}
	RECORD.emits = {}
	RECORD.moved = {}
	RECORD.rateEmitters = {}
	RECORD.lightsMaxRange = 0
	local warnings = {}
	RECORD.warn = function(message)
		warnings[message] = (warnings[message] or 0) + 1
	end
	local report = { name = name, timeScale = timeScale, warnings = warnings }

	local module = VFX.Effects:FindFirstChild(name)
	local ok, def = xpcall(require, debug.traceback, module)
	if not ok then
		report.error = "require failed: " .. tostring(def)
		return report
	end

	local startCreated = RECORD.created
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = container
	local params = table.clone(def.Defaults or {})
	for key, value in overrides do
		params[key] = value
	end
	local cframe = CFrame.lookAt(Vector3.new(0, 3, 0), Vector3.new(0, 3, 12)) -- LookVector toward a viewer at +Z
	local ctx = { CFrame = cframe, Params = params, Folder = folder, TimeScale = timeScale }
	function ctx.Wait(seconds)
		return task.wait(seconds / timeScale) * timeScale
	end
	function ctx.Tween(instance, seconds, props, style, direction)
		local tween = game:GetService("TweenService"):Create(instance, TweenInfo.new(seconds / timeScale, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
		tween:Play()
		return tween
	end
	function ctx.Emit(emitter, n)
		emitter.TimeScale = timeScale
		emitter:Emit(n)
	end
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
	function ctx.Forge()
		error("ctx.Forge is not available in the test runtime")
	end

	local start = Runtime.now()
	local returnedAt, destroyAt, done
	task.spawn(function()
		local okPlay, err = xpcall(def.Play, debug.traceback, ctx)
		if not okPlay then
			report.error = tostring(err)
		end
		returnedAt = Runtime.now()
		ctx.Wait(def.Linger or 1)
		destroyAt = Runtime.now()
		-- mesh particles still being simulated when the folder goes are cut off
		local cut = 0
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") and Runtime.isMovedRecently(d, 2 / 60) then
				cut += 1
			end
		end
		report.meshCut = cut
		folder:Destroy()
		done = true
	end)

	local peak = { instances = 0 }
	local classPeak = {}
	local seenTs = 0
	while not done and Runtime.now() - start < 60 do
		Runtime.step()
		for i = seenTs + 1, #RECORD.emits do
			local e = RECORD.emits[i]
			e.ts = e.emitter._props.TimeScale or 1
		end
		seenTs = #RECORD.emits
		local descendants = folder:GetDescendants()
		peak.instances = math.max(peak.instances, #descendants)
		local classes = {}
		for _, d in descendants do
			local class = d.ClassName
			if class == "Part" or class == "MeshPart" then
				class = "BasePart"
			end
			count(classes, class)
		end
		for class, n in classes do
			classPeak[class] = math.max(classPeak[class] or 0, n)
		end
	end
	if not done then
		report.error = (report.error or "") .. "\nnever finished within 60 s (Play or Linger hangs)"
		return report
	end

	-- particles, in real seconds
	local total, lastDeath, cutParticles, cutLate = 0, 0, 0, 0
	local events = {}
	for _, e in RECORD.emits do
		local life = e.life / math.max(e.ts or 1, 1e-6) * timeScale
		local death = e.time + e.life / math.max(e.ts or 1, 1e-6)
		total += e.count
		lastDeath = math.max(lastDeath, death)
		if death > destroyAt + 0.02 then
			cutParticles += e.count
			cutLate = math.max(cutLate, death - destroyAt)
		end
		table.insert(events, { e.time, e.count })
		table.insert(events, { death, -e.count })
		local _ = life
	end
	table.sort(events, function(a, b)
		return a[1] < b[1]
	end)
	local alive, peakAlive = 0, 0
	for _, ev in events do
		alive += ev[2]
		peakAlive = math.max(peakAlive, alive)
	end
	-- busiest one-second window of emission
	local peakRate = 0
	for i, e in RECORD.emits do
		local n = 0
		for j = i, #RECORD.emits do
			if RECORD.emits[j].time - e.time >= 1 then
				break
			end
			n += RECORD.emits[j].count
		end
		peakRate = math.max(peakRate, n)
	end

	local leftover = {}
	for _, d in workspace:GetDescendants() do
		if d.Name ~= "Ground" and d.Name ~= "TestWeapon" and d ~= container and not d:IsDescendantOf(container) then
			table.insert(leftover, d.ClassName .. " " .. d.Name)
		end
	end

	report.returnedAt = (returnedAt - start) * timeScale
	report.linger = def.Linger
	report.particles = total
	report.peakAlive = peakAlive
	report.peakRate = peakRate
	report.cutParticles = cutParticles
	report.cutLate = cutLate
	report.peakInstances = peak.instances
	report.classPeak = classPeak
	report.created = RECORD.created - startCreated
	report.lightRange = RECORD.lightsMaxRange
	report.leftover = leftover
	return report
end

local function fmt(n)
	return string.format("%.2f", n)
end

local failed = 0
for _, case in EFFECTS do
	for _, ts in { 1, 0.25 } do
		local r = runCase(case, ts)
		local label = r.name .. (if next(case[2] or {}) then " (" .. (case[3] or "overrides") .. ")" else "") .. (if ts ~= 1 then " @" .. ts .. "x" else "")
		if r.error then
			failed += 1
			print("FAIL " .. label .. "\n" .. r.error)
		elseif ts == 1 then
			local classes = {}
			for class, n in r.classPeak do
				table.insert(classes, class .. " " .. n)
			end
			table.sort(classes)
			print(("ok   %s: Play returned at %s s, Linger %s; particles %d (peak alive %d, peak %d/s); instances peak %d [%s]; light range max %s")
				:format(label, fmt(r.returnedAt), fmt(r.linger or 0), r.particles, r.peakAlive, r.peakRate, r.peakInstances, table.concat(classes, ", "), fmt(r.lightRange)))
			if r.cutParticles > 0 then
				print(("     WARN %d particles still alive when the folder is destroyed (up to %s s too early): raise Linger"):format(r.cutParticles, fmt(r.cutLate)))
			end
			if (r.meshCut or 0) > 0 then
				print(("     WARN %d mesh particles still moving when the folder is destroyed: raise Linger"):format(r.meshCut))
			end
			if #r.leftover > 0 then
				print("     WARN left outside ctx.Folder: " .. table.concat(r.leftover, ", "))
			end
		else
			print("ok   " .. label)
		end
		for message, n in r.warnings do
			print(("     WARN %s (x%d)"):format(message, n))
		end
	end
end
print(if failed == 0 then "ALL OK" else failed .. " FAILED")
