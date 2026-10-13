-- LocalScript: StarterPlayer/StarterPlayerScripts/Client/WindSwordReplicator
-- Plays other players' Wind Sword slashes (relayed by WindSwordServer).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VFXPlayer = require(Shared:WaitForChild("VFX"):WaitForChild("VFXPlayer"))
local WindSword = require(Shared:WaitForChild("WindSword"))

WindSword.Remote.OnClientEvent:Connect(function(character, tool)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local handle = tool and tool:FindFirstChild("Handle")
	if not (root and handle) then
		return
	end
	VFXPlayer.Play(WindSword.Effect, root.CFrame, { Weapon = handle, WindupTime = WindSword.WindupTime })
end)
