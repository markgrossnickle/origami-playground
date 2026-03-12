local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Environment = require(ReplicatedStorage.Shared.Environment)

return {
	Name = "game-environment",
	Description = "Returns what environment this game is running in",
	Group = "group",
	Args = {},
	ClientRun = function(_context)
		return Environment
	end,
}
