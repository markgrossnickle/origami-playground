--!strict
return {
	Name = "setconfig",
	Aliases = { "config-set" },
	Description = "Override a config value at runtime (e.g., setconfig Player.MaxHP 200)",
	Group = "group",
	Args = {
		{
			Type = "string",
			Name = "path",
			Description = "Dot-separated config path (e.g., Player.MaxHP)",
		},
		{
			Type = "string",
			Name = "value",
			Description = "New value (numbers and booleans auto-converted)",
		},
	},
}
