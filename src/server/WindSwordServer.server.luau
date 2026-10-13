-- Script: ServerScriptService/Server/WindSwordServer
-- Relays Wind Sword slashes to every other player. The attacking client already
-- plays its own copy; the server only checks the request (sword equipped,
-- cooldown) and forwards the character and sword so other clients can play it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WindSword = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WindSword"))

local lastSlash = {}

WindSword.Remote.OnServerEvent:Connect(function(player)
	local character = player.Character
	local tool = character and character:FindFirstChild(WindSword.ToolName)
	if not (tool and tool:IsA("Tool")) then
		return
	end
	local now = os.clock()
	if now - (lastSlash[player] or 0) < WindSword.ServerCooldown then
		return
	end
	lastSlash[player] = now

	for _, other in Players:GetPlayers() do
		if other ~= player then
			WindSword.Remote:FireClient(other, character, tool)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastSlash[player] = nil
end)
