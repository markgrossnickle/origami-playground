--!strict
return {
	Name = "getconfig",
	Aliases = { "config-get" },
	Description = "Read a config value (e.g., getconfig Player.MaxHP)",
	Group = "group",
	Args = {
		{
			Type = "string",
			Name = "path",
			Description = "Dot-separated config path (e.g., Player.MaxHP)",
		},
	},
}
