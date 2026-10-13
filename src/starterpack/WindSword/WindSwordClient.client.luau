-- LocalScript: StarterPack/WindSword/WindSwordClient
-- Click while holding the sword: plays the slash animation and the wind spin-slash
-- (windup trail on this blade, then the vortex), and tells the server so other
-- players see it too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VFXPlayer = require(Shared:WaitForChild("VFX"):WaitForChild("VFXPlayer"))
local WindSword = require(Shared:WaitForChild("WindSword"))

local tool = script.Parent
local handle = tool:WaitForChild("Handle")

local ready = true

tool.Activated:Connect(function()
	if not ready then
		return
	end
	local character = tool.Parent
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	ready = false

	-- The default Animate script plays its tool slash animation when it sees this
	local toolAnim = Instance.new("StringValue")
	toolAnim.Name = "toolanim"
	toolAnim.Value = "Slash"
	toolAnim.Parent = tool

	VFXPlayer.Play(WindSword.Effect, root.CFrame, { Weapon = handle, WindupTime = WindSword.WindupTime })
	WindSword.Remote:FireServer()

	task.delay(WindSword.Cooldown, function()
		ready = true
	end)
end)
