--!strict

return {
	Name = "setcranes",
	Aliases = { "cranes" },
	Description = "Set a player's cranes balance",
	Group = "group",
	Args = {
		{
			Type = "player",
			Name = "player",
			Description = "Target player",
		},
		{
			Type = "number",
			Name = "amount",
			Description = "Cranes amount (0-99999)",
		},
	},
}
