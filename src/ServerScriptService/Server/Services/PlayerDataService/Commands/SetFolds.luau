--!strict

return {
	Name = "setfolds",
	Aliases = { "folds" },
	Description = "Set a player's folds balance",
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
			Description = "Folds amount (0-999999)",
		},
	},
}
