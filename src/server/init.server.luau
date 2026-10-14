-- Script: ServerScriptService/Server
-- ForgeVFX registers the collision groups its debris and shockwave layers use;
-- that has to happen on the server. Effects themselves play on the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ForgeVFX = require(ReplicatedStorage.Shared:WaitForChild("Packages"):WaitForChild("ForgeVFX"))
ForgeVFX.init()
