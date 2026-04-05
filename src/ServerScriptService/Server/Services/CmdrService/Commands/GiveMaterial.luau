return {
	Name = "givemat",
	Aliases = { "gm" },
	Description = "Give materials to a player.",
	Group = "admin",
	Args = {
		{
			Type = "player",
			Name = "Target",
			Description = "Player to give materials to",
		},
		{
			Type = "MaterialId",
			Name = "Material",
			Description = "Material ID to give",
		},
		{
			Type = "positiveInteger",
			Name = "Amount",
			Description = "How many to give",
			Default = 100,
		},
	},
}
