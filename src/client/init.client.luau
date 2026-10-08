-- LocalScript: StarterPlayer/StarterPlayerScripts/VFXHarness
-- Studio-only test bench for effects in ReplicatedStorage/VFX/Effects.
--
--   Click an effect button to play it on the target dummy.
--   [R] replay   [L] loop   [ / ] slower / faster   [T] move target here
--   [P] print current params as a Luau table (paste into Defaults)
--
-- Live tuning: during Play, select Workspace > VFXHarnessConfig > <Effect>
-- and edit its Attributes in the Properties panel. The next play uses them.
-- Attribute edits are lost when you stop, so press P and paste first.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXFolder = ReplicatedStorage.Shared:WaitForChild("VFX")
local VFXPlayer = require(VFXFolder:WaitForChild("VFXPlayer"))
local Effects = VFXFolder:WaitForChild("Effects")

local player = Players.LocalPlayer
local SPEEDS = { 0.1, 0.25, 0.5, 1 }
local speedIndex = #SPEEDS
local current = nil
local looping = false

---------------------------------------------------------------- config
local config = Instance.new("Configuration")
config.Name = "VFXHarnessConfig"
config.Parent = workspace

local function configFor(name)
	local existing = config:FindFirstChild(name)
	if existing then
		return existing
	end
	local c = Instance.new("Configuration")
	c.Name = name
	c.Parent = config
	local def = require(Effects:FindFirstChild(name))
	for key, value in def.Defaults or {} do
		local ok = pcall(c.SetAttribute, c, key, value)
		if not ok then
			warn(("VFXHarness: '%s.%s' can't be an attribute (type %s)"):format(name, key, typeof(value)))
		end
	end
	return c
end

---------------------------------------------------------------- target
local target = Instance.new("Part")
target.Name = "VFXTarget"
target.Anchored = true
target.CanCollide = false
target.Size = Vector3.new(2, 5, 1)
target.Transparency = 0.6
target.Color = Color3.fromRGB(90, 90, 100)
target.Parent = workspace

local function placeTarget()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local pos = root.Position + root.CFrame.LookVector * 12
	-- Face the player so the effect's LookVector points at the camera side
	target.CFrame = CFrame.lookAt(pos, Vector3.new(root.Position.X, pos.Y, root.Position.Z))
end

player.CharacterAdded:Connect(function(character)
	character:WaitForChild("HumanoidRootPart")
	placeTarget()
end)
if player.Character then
	task.defer(placeTarget)
end

---------------------------------------------------------------- playback
local function play(name)
	current = name
	VFXPlayer.TimeScale = SPEEDS[speedIndex]
	VFXPlayer.Play(name, target.CFrame, configFor(name):GetAttributes())
end

local function toLuau(value)
	local t = typeof(value)
	if t == "Color3" then
		return ("Color3.fromRGB(%d, %d, %d)"):format(
			math.round(value.R * 255), math.round(value.G * 255), math.round(value.B * 255))
	elseif t == "Vector3" then
		return ("Vector3.new(%g, %g, %g)"):format(value.X, value.Y, value.Z)
	elseif t == "string" then
		return ("%q"):format(value)
	end
	return tostring(value)
end

local function printParams()
	if not current then
		return
	end
	local attrs = configFor(current):GetAttributes()
	local keys = {}
	for key in attrs do
		table.insert(keys, key)
	end
	table.sort(keys)
	local lines = { ("-- %s"):format(current), "Effect.Defaults = {" }
	for _, key in keys do
		table.insert(lines, ("\t%s = %s,"):format(key, toLuau(attrs[key])))
	end
	table.insert(lines, "}")
	print(table.concat(lines, "\n"))
end

---------------------------------------------------------------- UI
local gui = Instance.new("ScreenGui")
gui.Name = "VFXHarness"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Position = UDim2.fromOffset(10, 10)
panel.Size = UDim2.fromOffset(220, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
panel.BackgroundTransparency = 0.15
panel.Parent = gui

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local status = Instance.new("TextLabel")
status.LayoutOrder = 0
status.Size = UDim2.new(1, 0, 0, 0)
status.AutomaticSize = Enum.AutomaticSize.Y
status.BackgroundTransparency = 1
status.TextColor3 = Color3.new(1, 1, 1)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextWrapped = true
status.Font = Enum.Font.Code
status.TextSize = 13
status.Parent = panel

local function refreshStatus()
	status.Text = ("Speed %.2fx | Loop %s\n%s\nR replay  L loop  [ ] speed\nT move target  P print params")
		:format(SPEEDS[speedIndex], looping and "ON" or "off", current and ("> " .. current) or "> (none)")
end

local names = {}
for _, child in Effects:GetChildren() do
	if child:IsA("ModuleScript") then
		table.insert(names, child.Name)
	end
end
table.sort(names)

for i, name in names do
	local button = Instance.new("TextButton")
	button.LayoutOrder = i
	button.Size = UDim2.new(1, 0, 0, 26)
	button.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 14
	button.Text = name
	button.Parent = panel
	button.Activated:Connect(function()
		play(name)
		refreshStatus()
	end)
	configFor(name) -- create attributes up front so they're editable immediately
end

refreshStatus()

---------------------------------------------------------------- input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.R and current then
		play(current)
	elseif key == Enum.KeyCode.L then
		looping = not looping
	elseif key == Enum.KeyCode.LeftBracket then
		speedIndex = math.max(1, speedIndex - 1)
	elseif key == Enum.KeyCode.RightBracket then
		speedIndex = math.min(#SPEEDS, speedIndex + 1)
	elseif key == Enum.KeyCode.T then
		placeTarget()
	elseif key == Enum.KeyCode.P then
		printParams()
	end
	refreshStatus()
end)

task.spawn(function()
	while true do
		if looping and current then
			play(current)
		end
		task.wait(1.5 / SPEEDS[speedIndex])
	end
end)