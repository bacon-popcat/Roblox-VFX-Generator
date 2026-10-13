-- ModuleScript: ReplicatedStorage/Shared/WindSword
-- Shared settings for the Wind Sword tool (StarterPack/WindSword), its server
-- relay (ServerScriptService/Server/WindSwordServer) and the client that plays
-- other players' slashes (StarterPlayerScripts/Client/WindSwordReplicator).

local WindSword = {}

WindSword.ToolName = "WindSword"
WindSword.Cooldown = 1.0 -- seconds between slashes (client)
WindSword.ServerCooldown = 0.9 -- server check; a little lower to allow for latency
WindSword.WindupTime = 0.35 -- seconds of wind on the blade before the slash fires
WindSword.Effect = "WindSpinSlashCombo"

WindSword.Remote = script:WaitForChild("Slash")

return WindSword
