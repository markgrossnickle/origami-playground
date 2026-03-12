--!strict
return {
	Name = "resetconfig",
	Aliases = { "config-reset" },
	Description = "Reset a config override back to baseline value",
	Group = "group",
	Args = {
		{
			Type = "string",
			Name = "path",
			Description = "Dot-separated config path (e.g., Player.MaxHP)",
		},
	},
}
