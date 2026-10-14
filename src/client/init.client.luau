-- LocalScript: StarterPlayer/StarterPlayerScripts/Client (the VFXHarness)
-- Test bench for effects in ReplicatedStorage/Shared/VFX/Effects. Runs in
-- Studio and in the live place, so it can be tried on a phone.
--
--   Click an effect button to play it on the target dummy.
--   [R] replay   [L] loop   [ / ] slower / faster   [T] move target here
--   [P] print current params as a Luau table (paste into Defaults)
-- Every key also has an on-screen button for touch; "Hide" collapses the panel.
--
-- Live tuning: during Play, select Workspace > VFXHarnessConfig > <Effect>
-- and edit its Attributes in the Properties panel. The next play uses them.
-- Attribute edits are lost when you stop, so press P and paste first.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXFolder = ReplicatedStorage.Shared:WaitForChild("VFX")
local VFXPlayer = require(VFXFolder:WaitForChild("VFXPlayer"))
local Effects = VFXFolder:WaitForChild("Effects")

local player = Players.LocalPlayer
local SPEEDS = { 0.1, 0.25, 0.5, 1, 1.25, 1.5, 2}
local speedIndex = 4
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

---------------------------------------------------------------- actions
-- Shared by the keyboard shortcuts and the on-screen buttons (touch).
local actions = {
	{ label = "Replay", key = Enum.KeyCode.R, run = function()
		if current then
			play(current)
		end
	end },
	{ label = "Loop", key = Enum.KeyCode.L, run = function()
		looping = not looping
	end },
	{ label = "Target", key = Enum.KeyCode.T, run = placeTarget },
	{ label = "Slower", key = Enum.KeyCode.LeftBracket, run = function()
		speedIndex = math.max(1, speedIndex - 1)
	end },
	{ label = "Faster", key = Enum.KeyCode.RightBracket, run = function()
		speedIndex = math.min(#SPEEDS, speedIndex + 1)
	end },
	{ label = "Print", key = Enum.KeyCode.P, run = printParams },
}

---------------------------------------------------------------- UI
local isTouch = UserInputService.TouchEnabled
local BUTTON_HEIGHT = if isTouch then 36 else 26
local PANEL_WIDTH = if isTouch then 240 else 220
-- On touch, leave the bottom of the screen free for the thumbstick
local MAX_HEIGHT_FRACTION = if isTouch then 0.6 else 1

local gui = Instance.new("ScreenGui")
gui.Name = "VFXHarness"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("ScrollingFrame")
panel.Position = UDim2.fromOffset(10, 10)
panel.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
panel.CanvasSize = UDim2.new()
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.ScrollingDirection = Enum.ScrollingDirection.Y
panel.ScrollBarThickness = 4
panel.BorderSizePixel = 0
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

local function makeButton(text, parent)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	button.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 14
	button.Text = text
	button.Parent = parent
	return button
end

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

local hideButton = makeButton("Hide", panel)
hideButton.LayoutOrder = 1
hideButton.BackgroundColor3 = Color3.fromRGB(30, 30, 38)

local controls = Instance.new("Frame")
controls.LayoutOrder = 2
controls.Size = UDim2.new(1, 0, 0, 0)
controls.AutomaticSize = Enum.AutomaticSize.Y
controls.BackgroundTransparency = 1
controls.Parent = panel

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(1 / 3, -4, 0, BUTTON_HEIGHT)
grid.CellPadding = UDim2.fromOffset(4, 4)
grid.FillDirectionMaxCells = 3
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = controls

local effectList = Instance.new("Frame")
effectList.LayoutOrder = 3
effectList.Size = UDim2.new(1, 0, 0, 0)
effectList.AutomaticSize = Enum.AutomaticSize.Y
effectList.BackgroundTransparency = 1
effectList.Parent = panel

local effectLayout = Instance.new("UIListLayout")
effectLayout.Padding = UDim.new(0, 4)
effectLayout.SortOrder = Enum.SortOrder.LayoutOrder
effectLayout.Parent = effectList

local loopButton

local function refreshStatus()
	local lines = {
		("Speed %.2fx | Loop %s"):format(SPEEDS[speedIndex], looping and "ON" or "off"),
		current and ("> " .. current) or "> (none)",
	}
	if UserInputService.KeyboardEnabled then
		table.insert(lines, "R replay  L loop  [ ] speed\nT move target  P print params")
	end
	status.Text = table.concat(lines, "\n")
	loopButton.BackgroundColor3 = if looping then Color3.fromRGB(70, 110, 70) else Color3.fromRGB(45, 45, 55)
end

for i, action in actions do
	local button = makeButton(action.label, controls)
	button.LayoutOrder = i
	button.TextSize = 13
	button.Activated:Connect(function()
		action.run()
		refreshStatus()
	end)
	if action.label == "Loop" then
		loopButton = button
	end
end

local names = {}
for _, child in Effects:GetChildren() do
	if child:IsA("ModuleScript") then
		table.insert(names, child.Name)
	end
end
table.sort(names)

for i, name in names do
	local button = makeButton(name, effectList)
	button.LayoutOrder = i
	button.Activated:Connect(function()
		play(name)
		refreshStatus()
	end)
	configFor(name) -- create attributes up front so they're editable immediately
end

-- Grow with the content, but scroll instead of running off small screens
local function fitPanel()
	local viewport = workspace.CurrentCamera.ViewportSize
	local maxHeight = viewport.Y * MAX_HEIGHT_FRACTION - 20
	local contentHeight = layout.AbsoluteContentSize.Y + 16
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, math.min(contentHeight, maxHeight))
end
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitPanel)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel)

-- Collapse to just the status line so the effect isn't covered on a phone
hideButton.Activated:Connect(function()
	local show = not controls.Visible
	controls.Visible = show
	effectList.Visible = show
	hideButton.Text = if show then "Hide" else "Show"
end)

refreshStatus()
fitPanel()

---------------------------------------------------------------- input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	for _, action in actions do
		if input.KeyCode == action.key then
			action.run()
			refreshStatus()
			return
		end
	end
end)

task.spawn(function()
	while true do
		if looping and current then
			play(current)
		end
		task.wait(1.5 / SPEEDS[speedIndex])
	end
end)