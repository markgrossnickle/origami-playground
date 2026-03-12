--!strict

return {
	Name = "reset-data",
	Aliases = { "data-reset" },
	Description = "Permanently reset your profile and kick yourself from the game",
	Group = "group",
	Args = {
		{
			Type = "string",
			Name = "FOREVER",
			Description = "Must be the string FOREVER to confirm the reset",
		},
	},
}
