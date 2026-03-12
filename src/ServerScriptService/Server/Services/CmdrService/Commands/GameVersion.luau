local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameVersion = require(ReplicatedStorage.Shared.GameVersion)

return {
	Name = "game-version",
	Aliases = { "version-game" },
	Description = "Displays the version of the game you are running.",
	Group = "group",
	Args = {},
	ClientRun = function(_context)
		return GameVersion
	end,
}
